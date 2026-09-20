#!/usr/bin/env bash
# Case 03: a direct (non-proxy) connection to an unlisted intranet IP:port
# shellcheck source=/dev/null
# must be dropped by the firewall (this is the "no unexpected network" check).
# Also asserts L2 isolation: the container must sit on its own sandbox
# network inside the dedicated configured range (default 10.77.0.0/16),
# NOT on the default docker bridge shared with other host containers.
. "$(dirname "$0")/../common.sh"

# A public IP on a port that is surely not in any intranet-endpoints/host-ports
# list. Must take the full timeout (dropped, not refused) — anything non-zero
# exit from tcp_connect is a pass for us.
if tcp_connect 8.8.8.8 443 >/dev/null 2>&1; then
  fail "unexpected successful direct connection to 8.8.8.8:443 (not in any allowlist)"
fi

# A private-range IP that is definitely not configured, same expectation.
if tcp_connect 10.255.255.1 22 >/dev/null 2>&1; then
  fail "unexpected successful direct connection to 10.255.255.1:22 (not in any allowlist)"
fi

# L2 isolation: the sandbox must run on its own dedicated docker network
# (created by the run front doors) inside the configured IP range, not on
# the shared default bridge.
CIDR="${SANDBOX_NETWORK_CIDR:-10.77.0.0/16}"
GW_IP="$(ip -4 route show default 2>/dev/null | awk 'NR==1{print $3}')"
if [[ -z "${GW_IP}" ]]; then
  fail "no default gateway found — sandbox network misconfigured"
fi

# Gateway must be inside the dedicated sandbox range.
if ! python3 - "${GW_IP}" "${CIDR}" <<'PY' 2>/dev/null
import ipaddress, sys
gw = ipaddress.ip_address(sys.argv[1])
net = ipaddress.ip_network(sys.argv[2])
sys.exit(0 if gw in net else 1)
PY
then
  fail "default gateway ${GW_IP} is not inside the dedicated sandbox range ${CIDR} (expected L2 isolation)"
fi

# The default docker bridge gateway (172.17.0.1) must NOT be reachable.
if tcp_connect 172.17.0.1 8080 >/dev/null 2>&1; then
  fail "unexpected successful connection to 172.17.0.1 (default docker bridge gateway) — sandbox is not L2-isolated"
fi

pass "direct connections to unlisted endpoints are blocked; L2-isolated on dedicated sandbox network (gw ${GW_IP}, range ${CIDR})"
