#!/usr/bin/env bash
# Helpers for security test cases.
# These run INSIDE the sandbox container as the 'dev' user (the same
# privileges the AI agent has). Source this file at the top of each case:
#   . "$(dirname "$0")/common.sh"
# A case exits 0 with a "PASS" line on success, 1 with a "FAIL" line on failure.

set -u

pass() {
  echo "PASS: ${1}"
  exit 0
}

fail() {
  echo "FAIL: ${1}"
  exit 1
}

# Connect to host:port within timeout seconds using bash's /dev/tcp.
# Prints the IP actually reached and returns 0 on success, 1 on failure.
tcp_connect() {
  local host="${1}"
  local port="${2}"
  local timeout_s="${3:-6}"
  local ip
  # Resolve hostname if needed (bash /dev/tcp does not resolve names)
  if [[ ! "${host}" =~ ^[0-9.]+$ ]]; then
    ip="$(getent hosts "${host}" 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1; exit}' || true)"
    [[ -z "${ip}" ]] && return 1
    host="${ip}"
  fi
  timeout "${timeout_s}" bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null \
    && { echo "${host}"; return 0; }
  return 1
}

# Expect a command to FAIL (non-zero exit). Usage: expect_fail "description" cmd args...
expect_fail() {
  local desc="${1}"; shift
  if "$@" >/dev/null 2>&1; then
    fail "${desc} — command unexpectedly succeeded: $*"
  fi
}

# Expect a command to SUCCEED (zero exit). Usage: expect_ok "description" cmd args...
expect_ok() {
  local desc="${1}"; shift
  if ! "$@" >/dev/null 2>&1; then
    fail "${desc} — command unexpectedly failed: $*"
  fi
}
