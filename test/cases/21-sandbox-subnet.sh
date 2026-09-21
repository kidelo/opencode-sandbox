#!/usr/bin/env bash
# Case 21: the container sits on its dedicated sandbox subnet inside the
# configured range (sandbox-network-cidr). Stronger than case 03 (gateway in
# range): this asserts the container's own interface IP and mask are a /24
# inside the configured CIDR, which only holds if ensure_sandbox_network()
# created the dedicated network at the derived /24.
# SKIPs when the interface can be neither enumerated nor the range is known.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

CIDR="${SANDBOX_NETWORK_CIDR:-}"
if [[ -z "${CIDR}" ]]; then
  echo "SKIP: SANDBOX_NETWORK_CIDR not injected by the runner"
  exit 0
fi

# Pick the interface carrying the default route.
IFACE="$(ip -4 route show default 2>/dev/null | awk 'NR==1{print $5}')"
if [[ -z "${IFACE}" ]]; then
  echo "SKIP: no default route / ip tool unavailable"
  exit 0
fi

ADDR="$(ip -4 addr show "${IFACE}" 2>/dev/null | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | awk '{print $2}' | head -n1)"
if [[ -z "${ADDR}" ]]; then
  echo "SKIP: could not read ${IFACE} inet address"
  exit 0
fi

echo "iface=${IFACE} address=${ADDR} range=${CIDR}"

# The container address must be a <ip>/24 (derived /24) with the IP inside
# the configured range — only true if ensure_sandbox_network() created the
# dedicated network at the derived /24. ADDR still carries its prefix here.
if ! python3 - "${ADDR}" "${CIDR}" <<'PY' 2>/dev/null
import ipaddress, sys
addr = ipaddress.ip_interface(sys.argv[1])       # e.g. 10.77.5.10/24
net = ipaddress.ip_network(sys.argv[2])
sys.exit(0 if (addr.ip in net and addr.network.prefixlen == 24) else 1)
PY
then
  fail "container address ${ADDR} is not a /24 inside the sandbox range ${CIDR} (dedicated network missing?)"
fi

pass "sandbox-network-cidr honoured: ${ADDR} is a /24 inside ${CIDR}"
