#!/bin/sh
# dhcpcd client configuration script

RUNSTATE_DIR=/var/run/pearbox/network/wan
LOCKFILE=${RUNSTATE_DIR}/ifstate-${interface}.lock
IFSTATEFILE=${RUNSTATE_DIR}/ifstate-${interface}.json
NETPLEX_PIDFILE="/var/run/netplex.pid"

# Output error messages to stderr
print_err() {
    SYSLOG_ERR_PREFIX=${SYSLOG_OUTPUT:+"<3>"}
    echo ${SYSLOG_ERR_PREFIX} $@ >&2
}

# Usage:
# die RET MESSAGE ...
#
# Print MESSAGE(s) and exit with RET
die() {
    RET=${1}
    shift
    print_err $@
    exit ${RET}
}

# Resource lock acquire
lockfile_acquire() {
    exec 9<>"${LOCKFILE}"
    flock -e 9
}

# Resource lock release
lockfile_release() {
    flock -u 9
}

# Clean up everything when (unexpected) exit
cleanup() {
    lockfile_release
    trap - EXIT INT QUIT TERM
}

# Ensure that all arguments are unique
uniqify() {
    result=
    for i; do
        case " $result " in
        *" $i "*) ;;
        *) result="$result${result:+ }$i" ;;
        esac
    done
    echo "$result"
}

# Reading and writing the same file via input/output redirecting may corrupt the contents.
# This function acts like the 'sponge' command in the GNU moreutils.
sponge() {
    local TMPFILE=$(mktemp)
    cat >"$TMPFILE"
    install -m0644 "$TMPFILE" "${1}"
}

mkdir -p "${RUNSTATE_DIR}"
lockfile_acquire
trap cleanup EXIT INT QUIT TERM

# We assume we only make DHCP on only one interface at once.

if ! STATE=$(jq -ceM '.' "$IFSTATEFILE" 2>/dev/null); then
    echo '{}' >"$IFSTATEFILE"
fi

if [ "$if_down" = "true" ]; then
    jq -M ". + {if_down: true, ip_bound: false, ip6_bound: false}" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
    kill -USR1 $(cat "${NETPLEX_PIDFILE}")
    exit 0
else
    jq -M ". + {if_down: false}" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
fi

case "$reason" in
BOUND | RENEW | RECONFIGURE | REBIND | REBOOT)
    # IPv4 address bound
    jq -M ". + {
        ip_bound: true,
        ip: \"${new_ip_address}\",
        cidr: ${new_subnet_cidr:-0},
        gateway: \"${new_routers}\",
        dns: \"${new_domain_name_servers}\"
    }" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
    ;;
STOP)
    # DHCPv4 stopped
    jq -M ". + {ip_bound: false}" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
    ;;
BOUND6 | RENEW6 | REBIND6 | REBOOT6)
    # IPv6 address bound

    # TODO:

    ;;
ROUTERADVERT)
    # Router advertisement event
    jq -M ". + {
        ip6_bound: true,
        ip6: \"${nd1_addr1}\",
        cidr6: ${nd1_prefix_information1_length:-0},
        prefix6: \"${nd1_prefix_information1_prefix}\",
        gateway6: \"${nd1_from}\",
        dns6: \"${nd1_rdnss1_servers}\"
    }" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
    ;;
STOP6)
    # DHCPv6 stopped
    jq -M ". + {ip6_bound: false}" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
    ;;
esac

kill -USR1 $(cat "${NETPLEX_PIDFILE}")
exit 0
