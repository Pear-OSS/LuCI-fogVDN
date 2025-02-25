#!/bin/sh
# PPPoE client configure script

RUNSTATE_DIR=/var/run/pearbox/network/wan
LOCKFILE=${RUNSTATE_DIR}/ifstate-${IFNAME}.lock
IFSTATEFILE=${RUNSTATE_DIR}/ifstate-${IFNAME}.json
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

sponge() {
    local TMPFILE=$(mktemp -t router_sponge_XXXX)
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

if [ x"${CONNECT_TIME:+0}" = x0 ]; then
    jq -M ". + {if_down: true, ip_bound: false, ip6_bound: false}" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
    kill -USR1 $(cat "${NETPLEX_PIDFILE}")
    dhcpcd -k "$IFNAME"
    exit 0
else
    jq -M ". + {if_down: false}" "$IFSTATEFILE" | sponge "$IFSTATEFILE"
fi

jq -M ". + {
        ip_bound: true,
        ip: \"${IPLOCAL}\",
        gateway: \"${IPREMOTE}\",
        dns: \"${DNS1}\"
    }" "$IFSTATEFILE" | sponge "$IFSTATEFILE"

kill -USR1 $(cat "${NETPLEX_PIDFILE}")

echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/disable_ipv6"
echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/use_tempaddr"
echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/autoconf"
echo 1 >"/proc/sys/net/ipv6/conf/${IFNAME}/forwarding"

if [ ! -e "/run/dhcpcd/${IFNAME}.pid" ]; then
    dhcpcd -f /etc/pearbox/network/misc/dhcpcd-pppoe.conf -c /etc/pearbox/network/misc/dhcpcd-run-hook.sh "$IFNAME"
fi

exit 0
