#!/bin/sh

################################################################################
# This script starts pear_router WAN configuration.
#
# Dependencies:
#
# - any POSIX shell implementations (/bin/sh)
# - coreutils: readlink dirname realpath test cat install printf tr head tail
#              sleep wc mkdir
# - util-linux: logger flock
# - dhcpcd
# - ppp >= 2.4.9 (with pppoe plugin)
# - jq
# - iproute2 (>= 4.14): ip
# - nftables: nft
# - procps-ng: kill
# - psmisc: killall
# - openssl
# - bc
# - sed
# - xxd
################################################################################

THIS_SCRIPT="$(readlink -f "${0}")"
THIS_DIR="$(dirname "$THIS_SCRIPT")"

RUNSTATE_DIR=/var/run/pearbox/network/wan
LOCKFILE="${RUNSTATE_DIR}/start_wan.lock"

ACTION=
INFILE=
RUNNING_CONF='{}'
RUNNING_CONF_FILE="$(realpath "${THIS_DIR}/../config/running_conf.json")"
RUNNING_CONF_TMPFILE=

DHCPCD_CONF="$(realpath "${THIS_DIR}/../misc/dhcpcd.conf")"
DHCPCD_RUN_HOOK="$(realpath "${THIS_DIR}/../misc/dhcpcd-run-hook.sh")"

PPPOE_OPTION="$(realpath "${THIS_DIR}/../misc/pppoe.option")"
PPPOE_HOOK="$(realpath "${THIS_DIR}/../misc/pppoe-hook.sh")"

NFTABLES_CONF="$(realpath "${THIS_DIR}/../misc/nftables.conf")"
NFTABLES_ACTION=

JQ_CHECK_DHCP="$(realpath ${THIS_DIR}/wan.d/check_dhcp.jq)"
JQ_CHECK_PPPOE="$(realpath ${THIS_DIR}/wan.d/check_pppoe.jq)"
JQ_CHECK_STATIC="$(realpath ${THIS_DIR}/wan.d/check_static.jq)"
JQ_CHECK_BRIDGE="$(realpath ${THIS_DIR}/wan.d/check_bridge.jq)"

HWADDR_PREFIX_DAT="$(realpath "${THIS_DIR}/wan.d/mac_prefixes.dat")"
HWADDR_PREFIXES="$(sed -e '/#.*/d' "$HWADDR_PREFIX_DAT")"
HWADDR_PREFIXES_COUNT="$(echo "$HWADDR_PREFIXES" | wc -w)"

# Output info messages
print_info() {
	if [ -n "$SYSLOG_OUTPUT" ]; then
		logger -p syslog.info -t "${THIS_SCRIPT##*/}[$$]" $@
	else
		echo $@
	fi
}

# Output error messages
print_err() {
	if [ -n "$SYSLOG_OUTPUT" ]; then
		logger -p syslog.err -t "${THIS_SCRIPT##*/}[$$]" $@
	else
		echo $@ >&2
	fi
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

# Resource lock acquisition
acquire_lockfile() {
	exec 9<>"${LOCKFILE}"
	flock -en 9 || die 127 cannot acquire resources, maybe another instance is running?
}

# Resource lock release
release_lockfile() {
	flock -u 9
}

# Clean up everything when (unexpected) exit
cleanup() {
	release_lockfile
	trap - EXIT INT QUIT TERM
	exit
}

# Reading and writing the same file via input/output redirecting may corrupt the contents.
# This function acts like the 'sponge' command in the GNU moreutils.
sponge() {
	local TMPFILE=$(mktemp)
	cat >"$TMPFILE"
	install -m0644 "$TMPFILE" "${1}"
}

stop_dhcp() {
	IFNAME="${1}"
	print_info stop "$IFNAME"

	dhcpcd -k "$IFNAME" 2>/dev/null
	if DHCPCD_PID=$(cat "/run/dhcpcd/${IFNAME}.pid" 2>/dev/null); then
		kill "$DHCPCD_PID" 2>/dev/null
	fi

	ip link set "$IFNAME" down
	ip address flush "$IFNAME"
	ip link delete "$IFNAME"
}

stop_pppoe() {
	IFNAME="${1}"
	print_info stop "$IFNAME"

	# DHCPCD is used to listen RA and configure IPv6 for the interface
	# and we should shut it down
	dhcpcd -k "$IFNAME" 2>/dev/null
	if DHCPCD_PID=$(cat "/run/dhcpcd/${IFNAME}.pid" 2>/dev/null); then
		kill "$DHCPCD_PID" 2>/dev/null
	fi

	PPPOE_PIDFILE="/run/ppp-${IFNAME}.pid"
	if PPPOE_PID=$(cat "$PPPOE_PIDFILE" 2>/dev/null | head -n 1 2>/dev/null); then
		[ -n "$PPPOE_PID" ] && kill "$PPPOE_PID"
	fi

	ip link set "${IFNAME}vlan" down
	ip address flush "${IFNAME}vlan"
	ip link delete "${IFNAME}vlan"
}

stop_static() {
	IFNAME="${1}"
	print_info stop "$IFNAME"

	ip link set "$IFNAME" down
	ip address flush "$IFNAME"
	ip link delete "$IFNAME"

	echo '{}' | jq '{if_down: true}' | sponge "${RUNSTATE_DIR}/ifstate-${IFNAME}.json"
}

do_stop() {
	IFNAME="${1}"

	TYPE=$(jq -rM ".${IFNAME}.type" "$RUNNING_CONF_FILE") || die 1 is "'running_conf.json'" corrupted?
	case "$TYPE" in
	dhcp) stop_dhcp "$IFNAME" ;;
	pppoe) stop_pppoe "$IFNAME" ;;
	static) stop_static "$IFNAME" ;;
	*) : ;;
	esac
}

do_stop_all() {
	IFNAMES=$(jq -rM 'keys | .[]' "$RUNNING_CONF_FILE") || die 1 is "'running_conf.json'" corrupted?
	for IFNAME in $IFNAMES; do
		do_stop "$IFNAME"
	done

	sleep 1
	killall -q pppd
	killall -q dhcpcd
}

# Convert interface aliases to kernel names
# since some programs cannot cope with aliases
retrieve_real_ifname() {
	ip -j link show "${1}" 2>/dev/null | jq -reM '.[0].ifname' 2>/dev/null
}

# Check and convert netmask to CIDR prefix length
convert_netmask() {
	NETMASK="${1}"
	CIDR=0
	TMP_NUM=$(echo "$NETMASK" | tr '.' ' ')
	TMP_NUM=$(printf '%02X' $TMP_NUM)
	TMP_NUM=$(echo "ibase=16; $TMP_NUM" | bc)

	while [ "$TMP_NUM" -gt 0 ]; do
		TMP_NUM_REM=$((TMP_NUM % 2))
		if [ x"$TMP_NUM_REM" = "x0" -a "$CIDR" -ge 1 ]; then
			return 1
		fi

		CIDR=$((CIDR + TMP_NUM_REM))
		TMP_NUM=$((TMP_NUM >> 1))
	done

	echo $CIDR
}

# Generate random MAC address from well-known prefixes
fake_hwaddr() {
	HWADDR_PREFIX=
	HWADDR_SUFFIX=$(head -c 3 /dev/urandom | xxd -ps -g 0)

	# Use openssl-dgst to generate predictable sequence from input,
	# to guarantee consistent MAC address for PPPoE devices.
	PASS=${1:-${HWADDR_SUFFIX}}
	ENC=$(echo "$PASS" | openssl dgst -sm3 -binary 2>/dev/null | xxd -c 0 -ps -u -g 0)
	HWADDR_SUFFIX=$(echo "$ENC" | head -c 6)

	# Calculate RANDOM % len(HWADDR_PREFIXES) + 1 because `cut` counts from 1
	HPX=$(echo "$ENC" | tail -c +7 | head -c 6)
	HPR=$(echo "ibase=16; a=${HPX}; ibase=A; 1+a%${HWADDR_PREFIXES_COUNT}" | bc 2>/dev/null)
	HWADDR_PREFIX=$(echo $HWADDR_PREFIXES | cut -d ' ' -f $HPR)

	HWADDR=$(echo ${HWADDR_PREFIX}${HWADDR_SUFFIX} | sed 's/../&:/g;s/.$//')
	echo $HWADDR
}

do_create_vlan() {
	NIC="${1}"
	IFNAME="${2}"
	VLANID="${3}"

	ip link delete "$IFNAME" 2>/dev/null || true
	ip link add link "$NIC" name "$IFNAME" type vlan id "$VLANID" || print_err cannot create VLAN "$IFNAME" on "$NIC" with id "$VLANID"
}

do_create_macvlan() {
	NIC="${1}"
	IFNAME="${2}"

	ip link delete "$IFNAME" 2>/dev/null || true
	ip link add link "$NIC" name "$IFNAME" type macvlan || print_err cannot create MACVLAN "$IFNAME" on "$NIC"
}

do_dhcp() {
	IFNAME="${1}"
	print_info start "$IFNAME"

	NIC=$(jq -rM ".${IFNAME}.nic" "$RUNNING_CONF_FILE")
	VLAN_ENABLED=$(jq -rM ".${IFNAME}.vlan_enabled" "$RUNNING_CONF_FILE")
	MAC_MANUAL=$(jq -rM ".${IFNAME}.mac_manual" "$RUNNING_CONF_FILE")

	ip address flush dev "$NIC"
	echo 1 >"/proc/sys/net/ipv6/conf/${NIC}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${NIC}/autoconf"
	ip link set "$NIC" nomaster
	ip link set "$NIC" up

	if [ x"$VLAN_ENABLED" = x1 ]; then
		VLANID=$(jq -rM ".${IFNAME}.vlan_id" "$RUNNING_CONF_FILE")
		do_create_vlan "$NIC" "$IFNAME" "$VLANID"
	else
		do_create_macvlan "$NIC" "$IFNAME"
	fi

	ip link set "$IFNAME" down

	if [ x"$MAC_MANUAL" = x1 ]; then
		LLADDR=$(jq -rM ".${IFNAME}.mac" "$RUNNING_CONF_FILE")
		ip link set "$IFNAME" address "$LLADDR"
	else
		NIC_LLADDR=$(ip -j link show "$NIC" 2>/dev/null | jq '.[0].address')
		ip link set "$IFNAME" address "$(fake_hwaddr "$IFNAME$NIC$NIC_LLADDR")"
	fi

	# Disable IPv6 autoconfiguration
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/use_tempaddr"
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/autoconf"
	echo 1 >"/proc/sys/net/ipv6/conf/${IFNAME}/forwarding"
	ip link set "$IFNAME" up

	# Call DHCP client
	dhcpcd -f "$DHCPCD_CONF" -c "$DHCPCD_RUN_HOOK" "$IFNAME"
}

do_pppoe() {
	IFNAME="${1}"
	print_info start "$IFNAME"

	PPP_IFNAME="${1}"
	NIC=$(jq -rM ".${IFNAME}.nic" "$RUNNING_CONF_FILE")
	PPP_USER=$(jq -rM ".${PPP_IFNAME}.username" "$RUNNING_CONF_FILE")
	PPP_PASSWORD=$(jq -rM ".${PPP_IFNAME}.password" "$RUNNING_CONF_FILE")
	VLAN_ENABLED=$(jq -rM ".${IFNAME}.vlan_enabled" "$RUNNING_CONF_FILE")
	MAC_MANUAL=$(jq -rM ".${IFNAME}.mac_manual" "$RUNNING_CONF_FILE")

	ip address flush dev "$NIC"
	echo 1 >"/proc/sys/net/ipv6/conf/${NIC}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${NIC}/autoconf"
	ip link set "$NIC" nomaster
	ip link set "$NIC" up

	PPP_VLAN="${IFNAME}"vlan
	if [ x"$VLAN_ENABLED" = x1 ]; then
		VLANID=$(jq -rM ".${IFNAME}.vlan_id" "$RUNNING_CONF_FILE")
		do_create_vlan "$NIC" "$PPP_VLAN" "$VLANID"
	else
		do_create_macvlan "$NIC" "$PPP_VLAN"
	fi

	ip link set "$PPP_VLAN" down

	if [ x"$MAC_MANUAL" = x1 ]; then
		LLADDR=$(jq -rM ".${IFNAME}.mac" "$RUNNING_CONF_FILE")
		ip link set "$IFNAME" address "$LLADDR"
	else
		ip link set "$PPP_VLAN" address "$(fake_hwaddr "$IFNAME$PPP_USER")"
	fi

	# Disable IPv6 autoconfiguration
	echo 1 >"/proc/sys/net/ipv6/conf/${PPP_VLAN}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${PPP_VLAN}/use_tempaddr"
	echo 0 >"/proc/sys/net/ipv6/conf/${PPP_VLAN}/autoconf"
	echo 1 >"/proc/sys/net/ipv6/conf/${PPP_VLAN}/forwarding"
	ip link set "$PPP_VLAN" up

	MTU=$(jq -rM ".${PPP_IFNAME}.pppoe_mtu" "$RUNNING_CONF_FILE")
	HOLDOFF=$(jq -rM ".${PPP_IFNAME}.pppoe_redial_delay" "$RUNNING_CONF_FILE")

	PPPD_VER=$(pppd --version | cut -d ' ' -f 3)
	__PPPD_VER_CMP=$(printf "${PPPD_VER}\n2.5.0" | sort -V | head -n 1)
	PPPD_OPT_V6SCRIPT=
	if [ x"$__PPPD_VER_CMP" = "x2.5.0" ]; then
		PPPD_OPT_V6SCRIPT="ipv6-up-script \"${PPPOE_HOOK}\" ipv6-down-script \"${PPPOE_HOOK}\""
	fi

	# Call PPP client
	eval pppd plugin pppoe.so \"nic-${PPP_VLAN}\" \
		ifname \"$PPP_IFNAME\" \
		linkname \"$PPP_IFNAME\" \
		user \"$PPP_USER\" password \"$PPP_PASSWORD\" \
		mtu \"$MTU\" mru \"$MTU\" \
		holdoff \"$HOLDOFF\" \
		file \"$PPPOE_OPTION\" \
		ip-up-script \"$PPPOE_HOOK\" \
		ip-down-script \"$PPPOE_HOOK\" \
		$PPPD_OPT_V6SCRIPT
}

do_static() {
	IFNAME="${1}"
	print_info start "$IFNAME"

	NIC=$(jq -rM ".${IFNAME}.nic" "$RUNNING_CONF_FILE")
	VLAN_ENABLED=$(jq -rM ".${IFNAME}.vlan_enabled" "$RUNNING_CONF_FILE")
	MAC_MANUAL=$(jq -rM ".${IFNAME}.mac_manual" "$RUNNING_CONF_FILE")
	IP4_ENABLED=$(jq -rM ".${IFNAME}.ipv4_enabled" "$RUNNING_CONF_FILE")
	IP6_ENABLED=$(jq -rM ".${IFNAME}.ipv6_enabled" "$RUNNING_CONF_FILE")

	ip address flush dev "$NIC"
	echo 1 >"/proc/sys/net/ipv6/conf/${NIC}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${NIC}/autoconf"
	ip link set "$NIC" nomaster
	ip link set "$NIC" up

	if [ x"$VLAN_ENABLED" = x1 ]; then
		VLANID=$(jq -rM ".${IFNAME}.vlan_id" "$RUNNING_CONF_FILE")
		do_create_vlan "$NIC" "$IFNAME" "$VLANID"
	else
		do_create_macvlan "$NIC" "$IFNAME"
	fi

	ip link set "$IFNAME" down

	if [ x"$MAC_MANUAL" = x1 ]; then
		LLADDR=$(jq -rM ".${IFNAME}.mac" "$RUNNING_CONF_FILE")
		ip link set "$IFNAME" address "$LLADDR"
	else
		NIC_LLADDR=$(ip -j link show "$NIC" 2>/dev/null | jq '.[0].address')
		ip link set "$IFNAME" address "$(fake_hwaddr "$IFNAME$NIC$NIC_LLADDR")"
	fi

	# Disable IPv6 autoconfiguration
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/use_tempaddr"
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/autoconf"
	echo 1 >"/proc/sys/net/ipv6/conf/${IFNAME}/forwarding"
	ip link set "$IFNAME" up

	echo '{}' | jq '{if_down: false}' | sponge "${RUNSTATE_DIR}/ifstate-${IFNAME}.json"

	if [ x"$IP4_ENABLED" = x1 ]; then
		IPADDR=$(jq -rM ".${IFNAME}.ipaddr" "$RUNNING_CONF_FILE")
		NETMASK=$(jq -rM ".${IFNAME}.netmask" "$RUNNING_CONF_FILE")

		PREFIX_LEN=$(convert_netmask "$NETMASK")
		ip address add "${IPADDR}/${PREFIX_LEN}" dev "$IFNAME"
	fi

	if [ x"$IP6_ENABLED" = x1 ]; then
		IPADDR=$(jq -rM ".${IFNAME}.ip6addr" "$RUNNING_CONF_FILE")
		PREFIX_LEN=$(jq -rM ".${IFNAME}.prefix6" "$RUNNING_CONF_FILE")

		ip address add "${IPADDR}/${PREFIX_LEN}" dev "$IFNAME"
	fi
}

do_bridge() {
	IFNAME="${1}"
	print_info start "$IFNAME"

	NIC=$(jq -rM ".${IFNAME}.nic" "$RUNNING_CONF_FILE")
	VLAN_ENABLED=$(jq -rM ".${IFNAME}.vlan_enabled" "$RUNNING_CONF_FILE")
	MAC_MANUAL=$(jq -rM ".${IFNAME}.mac_manual" "$RUNNING_CONF_FILE")

	ip address flush dev "$NIC"
	echo 1 >"/proc/sys/net/ipv6/conf/${NIC}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${NIC}/autoconf"
	ip link set "$NIC" nomaster
	ip link set "$NIC" up

	if [ x"$VLAN_ENABLED" = x1 ]; then
		VLANID=$(jq -rM ".${IFNAME}.vlan_id" "$RUNNING_CONF_FILE")
		do_create_vlan "$NIC" "$IFNAME" "$VLANID"
	else
		do_create_macvlan "$NIC" "$IFNAME"
	fi

	ip link set "$IFNAME" down

	if [ x"$MAC_MANUAL" = x1 ]; then
		LLADDR=$(jq -rM ".${IFNAME}.mac" "$RUNNING_CONF_FILE")
		ip link set "$IFNAME" address "$LLADDR"
	else
		NIC_LLADDR=$(ip -j link show "$NIC" 2>/dev/null | jq '.[0].address')
		ip link set "$IFNAME" address "$(fake_hwaddr "$IFNAME$NIC$NIC_LLADDR")"
	fi

	# Disable IPv6
	echo 1 >"/proc/sys/net/ipv6/conf/${IFNAME}/disable_ipv6"
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/use_tempaddr"
	echo 0 >"/proc/sys/net/ipv6/conf/${IFNAME}/autoconf"
	echo 1 >"/proc/sys/net/ipv6/conf/${IFNAME}/forwarding"
	ip link set "$IFNAME" up
}

do_start() {
	IFNAMES="${1}"

	DEFAULT_ON=$(jq -rM ".${IFNAME}.default_on" "$RUNNING_CONF_FILE")
	if [ x"$DEFAULT_ON" != x1 ]; then
		return
	fi

	TYPE=$(jq -rM ".${IFNAME}.type" "$RUNNING_CONF_FILE") || die 1 is "'running_conf.json'" corrupted?
	case "$TYPE" in
	dhcp) do_dhcp "$IFNAME" ;;
	pppoe) do_pppoe "$IFNAME" ;;
	static) do_static "$IFNAME" ;;
	bridge) do_bridge "$IFNAME" ;;
	*) : ;;
	esac
}

do_start_all() {
	echo 1 >"/proc/sys/net/ipv4/ip_forward"

	IFNAMES=$(jq -rM 'keys | .[]' "$RUNNING_CONF_FILE") || die 1 is "'running_conf.json'" corrupted?
	for IFNAME in $IFNAMES; do
		do_start "$IFNAME"
	done
}

check_with_jq() {
	INDEX="${1}"
	OBJ="${2}"
	JQ_FILE="${3}"

	IFNAME=$(echo "$OBJ" | jq -rM ".ifname")
	NIC_ALIAS=$(echo "$OBJ" | jq -rM ".nic")

	[ "$IFNAME" = "$NIC_ALIAS" ] && die 3 configuration ${INDEX} ifname and nic cannot be the same

	NIC=$(retrieve_real_ifname "$NIC_ALIAS") || die 1 no network interface named "'${NIC_ALIAS}'"

	[ "$IFNAME" = "$NIC" ] && die 3 configuration ${INDEX} ifname and nic cannot be the same

	OBJ=$(echo "$OBJ" | jq -ceM ". + {nic: \"${NIC}\"}")

	NEW_OBJ=$(echo "$OBJ" | jq -ceMf "$JQ_FILE") || die 3 WAN configuration index ${INDEX} invalid

	echo "$NEW_OBJ" | jq -sM '.[0] + .[1]' "$RUNNING_CONF_TMPFILE" - | sponge "$RUNNING_CONF_TMPFILE"
}

check_dhcp() {
	check_with_jq "${1}" "${2}" "$JQ_CHECK_DHCP"
}

check_pppoe() {
	check_with_jq "${1}" "${2}" "$JQ_CHECK_PPPOE"
}

check_static() {
	INDEX="${1}"
	OBJ="${2}"

	CHECK_STATIC_IFNAME=$(echo "$OBJ" | jq -rM ".ifname") || die 3 WAN configuration index ${INDEX} invalid
	check_with_jq "$INDEX" "$OBJ" "$JQ_CHECK_STATIC"
	CHECK_STATIC_NETMASK=$(jq -rM ".${CHECK_STATIC_IFNAME}.netmask" "$RUNNING_CONF_TMPFILE")
	if [ -n "$CHECK_STATIC_NETMASK" ]; then
		CHECK_STATIC_PREFIX=$(convert_netmask "$CHECK_STATIC_NETMASK") || die 3 WAN configuration index ${INDEX} invalid netmask
	fi
}

check_bridge() {
	check_with_jq "${1}" "${2}" "$JQ_CHECK_BRIDGE"
}

# Parse JSON input
parse_infile() {
	jq '.[0]' "$INFILE" >/dev/null 2>&1 || die 1 "'${INFILE}'" is not a legal input
	COUNT=$(jq -M 'length' "$INFILE")
	local NUM=0
	while [ "$NUM" -lt "$COUNT" ]; do
		OBJ=$(jq -cM ".[${NUM}]" "$INFILE")
		TYPE=$(echo "$OBJ" | jq -er '.type|tostring') || die 3 no "'type'" within WAN object index "$NUM"

		case "$TYPE" in
		dhcp) check_dhcp "$NUM" "$OBJ" ;;
		pppoe) check_pppoe "$NUM" "$OBJ" ;;
		static) check_static "$NUM" "$OBJ" ;;
		bridge) check_bridge "$NUM" "$OBJ" ;;
		wireless) : ;;
		*) die 3 unsupported WAN type "'${TYPE}'" ;;
		esac

		NUM=$((NUM + 1))
	done
}

# Generate new running configurations from input
mkconf() {
	RUNNING_CONF_TMPFILE=$(mktemp)
	echo '{}' >"$RUNNING_CONF_TMPFILE"
	parse_infile
}

do_reload() {
	mkconf

	# Stop network if old configuration found
	[ -f "$RUNNING_CONF_FILE" ] && do_stop_all

	sleep 1

	install -v "$RUNNING_CONF_TMPFILE" "$RUNNING_CONF_FILE"

	do_start_all
}

do_remove() {
	IFNAMES=$(jq -rM 'map(tostring)[]' "$INFILE")
	for IFNAME in $IFNAMES; do
		do_stop "$IFNAME"

		NIC=$(jq -rM ".${IFNAME}.nic" "$RUNNING_CONF_FILE")
		NIC_USAGE=$(jq -M "map(select(.nic == \"${NIC}\")) | length" "$RUNNING_CONF_FILE")

		# Delete from RUNNING_CONF_FILE
		jq -M "del(.${IFNAME})" "$RUNNING_CONF_FILE" | sponge "$RUNNING_CONF_FILE"

		# Add unused NIC to br-lan
		[ 0 -eq "$NIC_USAGE" ] 2>/dev/null && ip link set "$NIC" master br-lan 2>/dev/null

	done
}

do_update() {
	mkconf

	IFNAMES=$(jq -rM 'keys[]' "$RUNNING_CONF_TMPFILE")
	for IFNAME in $IFNAMES; do
		do_stop "$IFNAME"
	done

	sleep 1

	jq -sM '.[0] + .[1]' "$RUNNING_CONF_FILE" "$RUNNING_CONF_TMPFILE" | sponge "$RUNNING_CONF_FILE"

	for IFNAME in $IFNAMES; do
		do_start "$IFNAME"
	done
}

flush_nftables() {
	nft -f "$NFTABLES_CONF"
}

reload_nftables() {
	flush_nftables

	IFNAMES=$(jq -rM 'keys | .[]' "$RUNNING_CONF_FILE") || die 1 is "'running_conf.json'" corrupted?

	for IFNAME in $IFNAMES; do
		nft add element ip pear_router wan_ports "{ ${IFNAME} }"
		TYPE=$(jq -rM ".${IFNAME}.type" "$RUNNING_CONF_FILE")
		if [ x"$TYPE" = "xpppoe" ]; then
			nft add element inet pear_router ppp_ports "{ ${IFNAME} }"
		fi
	done
}

# Parse command line arguments
parse_command() {
	case "${1}" in
	reload)
		ACTION="RELOAD"
		NFTABLES_ACTION="RELOAD"
		INFILE="${2}"
		shift 2
		;;
	remove)
		ACTION="REMOVE"
		INFILE="${2}"
		shift 2
		;;
	update)
		ACTION="UPDATE"
		NFTABLES_ACTION="RELOAD"
		INFILE="${2}"
		shift 2
		;;

	restart)
		ACTION="RESTART"
		NFTABLES_ACTION="RELOAD"
		INFILE="${2}"
		if [ -z "$INFILE" ]; then
			shift
		else
			shift 2
		fi
		;;
	start)
		ACTION="START"
		NFTABLES_ACTION="RELOAD"
		INFILE="${2}"
		if [ -z "$INFILE" ]; then
			shift
		else
			shift 2
		fi
		;;
	stop)
		ACTION="STOP"
		INFILE="${2}"
		if [ -z "$INFILE" ]; then
			NFTABLES_ACTION="FLUSH"
			shift
		else
			shift 2
		fi
		;;
	*)
		die 2 unrecognized argument "'${1}'"
		;;
	esac

	if [ -n "${1}" ]; then
		die 2 unrecognized argument "'${1}'"
	fi
}

# Main entry
main() {
	if [ ! -f "$RUNNING_CONF_FILE" ]; then
		rm -f "$RUNNING_CONF_FILE"
		echo '{}' >"$RUNNING_CONF_FILE"
	fi

	case "${ACTION}" in
	RELOAD) do_reload ;;
	REMOVE) do_remove ;;
	UPDATE) do_update ;;

	RESTART)
		IFNAME="$INFILE"
		if [ -z "$IFNAME" ]; then
			do_stop_all
			do_start_all
		else
			HAS_IFNAME=$(jq -rM "has(\"${IFNAME}\")" "$RUNNING_CONF_FILE")
			if [ x"$HAS_IFNAME" = "xtrue" ]; then
				do_stop "$IFNAME"
				sleep 1
				do_start "$IFNAME"
			else
				die 1 no configuration for "'${IFNAME}'" to be restarted
			fi
		fi
		;;
	START)
		IFNAME="$INFILE"
		if [ -z "$IFNAME" ]; then
			do_start_all
		else
			HAS_IFNAME=$(jq -rM "has(\"${IFNAME}\")" "$RUNNING_CONF_FILE")
			if [ x"$HAS_IFNAME" = "xtrue" ]; then
				do_start "$IFNAME"
			else
				die 1 no configuration for "'${IFNAME}'" to be started
			fi
		fi
		;;
	STOP)
		IFNAME="$INFILE"
		if [ -z "$IFNAME" ]; then
			do_stop_all
		else
			HAS_IFNAME=$(jq -rM "has(\"${IFNAME}\")" "$RUNNING_CONF_FILE")
			if [ x"$HAS_IFNAME" = "xtrue" ]; then
				do_stop "$IFNAME"
			else
				die 1 no configuration for "'${IFNAME}'" to be stopped
			fi
		fi
		;;

	*) die 255 unexpected error ;;
	esac

	case "${NFTABLES_ACTION}" in
	RELOAD) reload_nftables ;;
	FLUSH) flush_nftables ;;
	*) : ;;
	esac
}

_init() {
	mkdir -p "${RUNSTATE_DIR}"
	acquire_lockfile
	trap cleanup EXIT INT QUIT TERM

	CGROUP_MOUNT=$(grep cgroup2 /proc/mounts | cut -d ' ' -f 2 | head -n 1)
	[ -z "$CGROUP_MOUNT" ] && return

	echo $$ >"${CGROUP_MOUNT}/cgroup.procs"

	NETPLEX_PID=$(cat /run/netplex.pid 2>/dev/null)
	[ -z "$NETPLEX_PID" ] && return

	NETPLEX_CGROUP=$(cat "/proc/${NETPLEX_PID}/cgroup" | cut -d ':' -f 3)
	[ -z "$NETPLEX_CGROUP" ] && return

	echo $$ >"${CGROUP_MOUNT}${NETPLEX_CGROUP}/cgroup.procs"
} && _init

parse_command "$@"
main
exit 0
