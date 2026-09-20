#!/usr/bin/env bash
# Case 02: no local credentials or sensitive files are reachable.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

for f in /etc/shadow /etc/gshadow /root/.ssh /home/dev/.bash_history; do
  if [[ -e "${f}" ]] && cat "${f}" >/dev/null 2>&1; then
    fail "sensitive file '${f}' is readable"
  fi
done

expect_fail "sudoers must not be readable" cat /etc/sudoers
expect_fail "/usr is not writable" touch /usr/.test-write 2>/dev/null
rm -f /usr/.test-write 2>/dev/null || true

# /opencode-password is mounted with owner-only perms for 'dev'
if [[ -e /opencode-password ]]; then
  perms="$(stat -c '%a' /opencode-password)"
  case "${perms}" in
    600) : ;;
    *) fail "/opencode-password has permissive mode ${perms} (expected 600)" ;;
  esac
fi

pass "no /etc/shadow, no /root access, no /usr write, password file owner-only"
