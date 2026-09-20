#!/usr/bin/env bash
# Case 01: agent runs as a non-root, unprivileged user.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

if [[ "$(id -u)" -eq 0 ]]; then
  fail "process is running as root"
fi
if getent group root > /dev/null 2>&1 && id -nG | grep -qw root; then
  fail "process is a member of the root group"
fi
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  fail "passwordless sudo works"
fi
expect_fail "su to root without password must fail" su -s /bin/bash root -c "id"

pass "runs as unprivileged user, no root group, no sudo/su"
