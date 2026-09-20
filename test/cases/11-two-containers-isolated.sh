#!/usr/bin/env bash
# Case 11: a second container that is running in parallel (started by the
# runner on a DIFFERENT network) must stay invisible from this sandbox:
# resolvable neither by name (Docker's built-in DNS is per-network) nor
# reachable by IP (no route between bridge networks). Proves live,
# two-container isolation — not only "one sandbox talking to a fixed IP".
# Runner contract: sets PEER_NAME and PEER_IP env vars when the peer is up.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

PEER_NAME="${PEER_NAME:-}"
PEER_IP="${PEER_IP:-}"
if [[ -z "${PEER_NAME}" || -z "${PEER_IP}" ]]; then
  echo "SKIP: peer container not started by the runner (PEER_NAME/PEER_IP unset)"
  exit 0
fi

echo "peer under test: ${PEER_NAME} (${PEER_IP}, different network)"

# 1) Name-based: Docker's embedded DNS only resolves names of containers that
#    share a network. The peer is on a different network -> must NOT resolve.
if getent hosts "${PEER_NAME}" >/dev/null 2>&1; then
  fail "peer container name '${PEER_NAME}' resolves from inside the sandbox (shared DNS domain — isolation broken)"
fi

# 2) IP-based: a direct TCP connection to the peer must fail (no route
#    between the network segments and/or dropped by the egress firewall).
if tcp_connect "${PEER_IP}" 80 5 >/dev/null 2>&1; then
  fail "direct TCP connection to peer container ${PEER_IP}:80 succeeded — cross-container communication possible"
fi

pass "second running container is isolated: name unresolvable, TCP to ${PEER_IP} blocked"
