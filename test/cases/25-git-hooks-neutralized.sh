#!/usr/bin/env bash
# Case 25: in-container git cannot fire user-planted hooks, even if the
# workspace /workspace/.git/hooks is not ro (a fresh repo). Proof: plant a
# probe pre-commit hook in a throwaway repo under /workspace, run a real
# commit, assert the hook did NOT fire (no marker file).
#
# The neutralization is `git config --system core.hooksPath /dev/null`
# (baked into the base image's /etc/gitconfig). The system scope is the
# fallback when the user's local /global scope does not set core.hooksPath,
# so a fresh `git init` gets its hooks neutralized; a user repo that pins
# core.hooksPath in .git/config (also ro-pinned by case 24) is unaffected by
# the agent either way.
. "$(dirname "$0")/../common.sh"

have git

# Throwaway repo — never touches the user's .git.
W="/workspace/.hooktest-$$"
MARKER="/tmp/.hook-fired-$$"
rm -rf "${W}" "${MARKER}" 2>/dev/null || true
mkdir -p "${W}"
cd "${W}" || fail "mkdir throwaway repo dir failed"
git init -q . 2>/dev/null || fail "throwaway git init failed"

# Plant a probe pre-commit hook that drops a marker file.
PROBE="${W}/.git/hooks/pre-commit"
printf '#!/bin/sh\ntouch %s\n' "${MARKER}" > "${PROBE}"
chmod +x "${PROBE}"

# A commit SHOULD succeed but MUST NOT fire the hook.
echo "probe" > a.txt
git add a.txt
git -c user.email=probe@probe -c user.name=probe commit -q -m "probe" 2>/dev/null \
  || fail "git commit in the throwaway repo failed (hooks config broken)"

# The marker must NOT have appeared.
if [[ -e "${MARKER}" ]]; then
  rm -f "${MARKER}" 2>/dev/null || true
  fail "planted git pre-commit hook FIRED on in-container commit — the auto-exec escape is live"
fi

# Clean up the throwaway repo so the workspace is not polluted.
rm -rf "${W}" 2>/dev/null || true

# Belt-and-braces: the system scope should report the neutralized value.
sys_hookspath="$(git config --system --get core.hooksPath 2>/dev/null || true)"
if [[ "${sys_hookspath}" == "/dev/null" ]]; then
  pass "git hooks neutralized (in-commit probe did NOT fire; system scope ${sys_hookspath})"
else
  pass "git hooks neutralized (in-commit probe did NOT fire; system scope=${sys_hookspath:-unset})"
fi
