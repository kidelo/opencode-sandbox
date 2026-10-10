#!/usr/bin/env bash
# Case 28: seccomp (Docker's built-in default allow-list profile) is ACTIVE
# for the dev process. /proc/self/status reports the seccomp mode:
#   0 = SECCOMP_MODE_DISABLED
#   2 = SECCOMP_MODE_FILTER   <- what we want
#   1 = SECCOMP_MODE_STRICT   (rare; also valid)
# We assert mode 2 (the common case). The 'seccomp: off' knob (an explicit
# opt-out) will SKIP this case.
. "$(dirname "$0")/../common.sh"

if [[ "${POLICY_SECCOMP:-on}" == "off" ]]; then
  echo "SKIP: project has 'seccomp: off' (Docker's default profile explicitly unconfined)"
  exit 0
fi

mode="$(awk '/^Seccomp:/{print $2}' /proc/self/status 2>/dev/null || true)"
case "${mode}" in
  2|1)   pass "seccomp mode ${mode} (a filter is attached — Docker's default allow-list profile is in force)" ;;
  0|"")  fail "seccomp is DISABLED (mode=${mode:-missing}) — the classic escape syscalls (ptrace, mount, unshare, bpf, …) are NOT blocked" ;;
  *)     fail "unexpected seccomp mode '${mode}' (expected 0, 1, or 2)" ;;
esac
