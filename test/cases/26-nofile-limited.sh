#!/usr/bin/env bash
# Case 26: RLIMIT_NOFILE (max open fds) is bounded, so a runaway agent cannot
# flood the host with file descriptors (a classic host-DoS). /proc/self/limits
# is dev-readable and cgroup-version independent.
. "$(dirname "$0")/../common.sh"

nofile="$(awk '/^Max open files/{print $4}' /proc/self/limits 2>/dev/null || true)"
if [[ -z "${nofile}" || "${nofile}" == "unlimited" ]]; then
  fail "RLIMIT_NOFILE not set (Max open files='${nofile:-missing}') — a runaway agent can DoS the host by opening millions of fds"
fi

# The default is 8192 (bin/shared). If the user configured a value, it must
# match exactly; otherwise the default must be finite.
if [[ -n "${POLICY_NOLFILE:-}" ]]; then
  if [[ "${nofile}" != "${POLICY_NOLFILE}" ]]; then
    fail "RLIMIT_NOFILE=${nofile} does not match configured 'nofile=${POLICY_NOLFILE}'"
  fi
fi

pass "RLIMIT_NOFILE=${nofile} (fd exhaustion DoS guarded)"
