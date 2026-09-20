#!/usr/bin/env bash
# Case 06: no docker escape channel.
# The image must provide NO way for the agent to reach the host Docker
# daemon: no mounted socket and no docker CLI. Both are a hard requirement —
# any container the agent could spawn on the host would defeat the sandbox.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

if [[ -S /var/run/docker.sock ]]; then
  fail "host docker socket /var/run/docker.sock is mounted — container-escape channel exists"
fi

if command -v docker >/dev/null 2>&1; then
  fail "docker CLI is installed in the image (found: $(command -v docker))"
fi

if command -v podman >/dev/null 2>&1; then
  fail "podman CLI is installed in the image (found: $(command -v podman))"
fi

pass "no docker escape channel: no socket, no docker/podman CLI"
