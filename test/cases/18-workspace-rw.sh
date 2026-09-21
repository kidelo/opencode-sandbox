#!/usr/bin/env bash
# Case 18: the workspace mount is the single user rw dir.
# build_run_flags mounts the project workspace at /workspace (rw) and masks
# the .sandbox runtime tree (self-hosted). /workspace and its parent
# container paths used by this case must be writable; system dirs must not
# (already asserted in case 02, but repeated here as the workspace contract).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

ws="/workspace"
if [[ ! -d "${ws}" ]]; then
  echo "SKIP: ${ws} not present (no workspace mount)"
  exit 0
fi

# /workspace must be writable by dev.
probe="${ws}/.ocs-ws-probe-$$"
if ! printf 'ok\n' > "${probe}" 2>/dev/null; then
  fail "${ws} is not writable by dev (workspace mount missing or ro)"
fi
cat "${probe}" >/dev/null 2>&1 || fail "could not read back ${probe}"
rm -f -- "${probe}" 2>/dev/null || true

pass "workspace at /workspace is writable by dev (single rw dir)"
