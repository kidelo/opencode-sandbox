#!/usr/bin/env bash
# Case 07: read-back of the firewall policy as a sanity baseline (informational).
# The agent runs as 'dev', which does not have CAP_NET_ADMIN, so iptables is
# usually denied inside. We still pass (this is a report, not an assertion);
# the hard egress-blocking signal comes from case 03.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

if iptables -L OUTPUT -n >/dev/null 2>&1; then
  echo "=== OUTPUT chain (IPv4) ==="
  iptables -L OUTPUT -n 2>/dev/null | sed -n '1,6p'
  echo "=== ACCEPT rules (host/intranet ports) ==="
  iptables -L OUTPUT -n 2>/dev/null | grep 'ACCEPT' | grep -E 'dpt:' || echo "(no port-specific ACCEPT visible)"
else
  echo "(iptables not available to current user — expected for 'dev'; the host can verify with: docker exec <container> iptables -L OUTPUT -n)"
fi
pass "firewall state reported (see output above)"
