#!/usr/bin/env bash
# Case 16: host-ports positive test.
# The runner publishes HARNESS_HOST_PORT on the host and starts a listener
# container behind it; the same port is baked into the TEST image's
# /etc/host-ports.txt (via build args, Dockerfile.test), so the entrypoint
# ACCEPTs docker.host:HARNESS_HOST_PORT. The test container may reach the
# host on that port ONLY through that rule (egress is default-deny). The
# adjacent unlisted port on docker.host must still be dropped.
# SKIPs when the runner did not start the host listener or inject the env.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

skip_if_empty HARNESS_HOST_PORT
[[ "${HOST_LISTENER_UP:-0}" == "1" ]] || { echo "SKIP: host-port listener not active (HOST_LISTENER_UP)"; exit 0; }

# Resolve docker.host (added by resolve_add_host_flag) to its IPv4 address.
HOST="$(getent hosts docker.host 2>/dev/null | awk '{ if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $1; exit } }')"
if [[ -z "${HOST}" ]]; then
  echo "SKIP: docker.host not resolvable in this container (run door without add-host?)"
  exit 0
fi

PORT="${HARNESS_HOST_PORT}"
if (( PORT >= 65535 )); then
  CONTRAST=1
else
  CONTRAST=$((PORT + 1))
fi

echo "host target: ${HOST}:${PORT} (contrast: ${HOST}:${CONTRAST})"

# Positive: the listed host port must be reachable through the listener.
if ! bash -c "exec 3<>/dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
  fail "host-ports not honoured: 'docker.host:${PORT}' (listed) is NOT reachable"
fi
echo "listed host port docker.host:${PORT} is reachable — ACCEPT rule in effect"

# Negative contrast: same host, adjacent unlisted port must be dropped.
if bash -c "exec 3<>/dev/tcp/${HOST}/${CONTRAST}" 2>/dev/null; then
  fail "host-ports too broad: 'docker.host:${CONTRAST}' (unlisted) is reachable"
fi
echo "contrast docker.host:${CONTRAST} (unlisted) is blocked — rule scoped to the listed port"

pass "host-ports works: listed docker.host:${PORT} reachable, adjacent ${CONTRAST} blocked"
