#!/usr/bin/env bash
# Case 17: config/opencode.jsonc is mounted read-only.
# build_run_flags mounts the project's opencode config to
# /etc/opencode/opencode.jsonc as :ro (so the agent reads but cannot rewrite
# it). The file must be present, human-readable, and NOT writable.
# SKIPs if the project has no opencode.jsonc (legacy layout / not mounted).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

CFG="/etc/opencode/opencode.jsonc"
if [[ ! -e "${CFG}" ]]; then
  echo "SKIP: ${CFG} not present (opencode config not mounted for this project)"
  exit 0
fi

# Readable (the entrypoint / agent must be able to read it).
if ! cat "${CFG}" >/dev/null 2>&1; then
  fail "cannot read ${CFG}"
fi

# Not writable — appending to the file must fail (the mount is :ro and/or
# the host file is not dev-owned; either way a write is not permitted).
if printf '\n' >> "${CFG}" 2>/dev/null; then
  fail "could append to ${CFG} — read-only config mount not enforced"
fi

pass "config/opencode.jsonc present, readable, and not writable (ro mount)"
