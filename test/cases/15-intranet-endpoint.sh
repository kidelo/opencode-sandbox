#!/usr/bin/env bash
# Case 15: intranet-endpoints positive test.
# The runner bakes <EP_IP>:<EP_PORT> into the TEST image's
# /etc/intranet-endpoints.txt (via build args, Dockerfile.test) and starts a
# listener container on the sandbox network at EP_IP:EP_PORT that accepts
# connections. The test container may reach it ONLY through the baked
# intranet ACCEPT rule (egress is default-deny). The adjacent unlisted port
# (EP_PORT+1) on the SAME ip must still be dropped — proving the rule is
# scoped to the listed ip:port and not a blanket allow for that ip.
# SKIPs when the runner did not start the listener or inject the harness env
# (run outside `ocs test`).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

skip_if_empty HARNESS_EP_IP HARNESS_EP_PORT
[[ "${EP_LISTENER_UP:-0}" == "1" ]] || { echo "SKIP: endpoint listener not active (EP_LISTENER_UP)"; exit 0; }

EP="${HARNESS_EP_IP}"
PORT="${HARNESS_EP_PORT}"
# +1 must stay in valid port range for the contrast probe.
if (( PORT >= 65535 )); then
  CONTRAST=1
else
  CONTRAST=$((PORT + 1))
fi

echo "endpoint target: ${EP}:${PORT} (contrast: ${EP}:${CONTRAST})"

# Positive: a listed endpoint must be reachable (the listener accepts).
# /dev/tcp opens a socket; success = the ACCEPT rule is in effect.
if ! bash -c "exec 3<>/dev/tcp/${EP}/${PORT}" 2>/dev/null; then
  fail "intranet-endpoints not honoured: '${EP}:${PORT}' (listed) is NOT reachable"
fi
echo "listed endpoint ${EP}:${PORT} is reachable — ACCEPT rule in effect"

# Negative contrast: same IP, adjacent unlisted port must be dropped.
if bash -c "exec 3<>/dev/tcp/${EP}/${CONTRAST}" 2>/dev/null; then
  fail "intranet-endpoints too broad: '${EP}:${CONTRAST}' (unlisted) is reachable"
fi
echo "contrast ${EP}:${CONTRAST} (unlisted) is blocked — rule scoped correctly"

pass "intranet-endpoints works: listed ${EP}:${PORT} reachable, adjacent ${CONTRAST} blocked"
