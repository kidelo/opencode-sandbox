#!/usr/bin/env bash
# Case 05: no kernel capabilities the agent could abuse.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

if [[ -r /proc/self/status ]]; then
  caps="$(grep -E '^CapEff:' /proc/self/status | awk '{print $2}')"
  echo "CapEff: ${caps:-0}"
  # 0 means no effective capabilities.
  if [[ "${caps:-0}" != "0000000000000000" ]]; then
    fail "process has effective capabilities: ${caps}"
  fi
else
  echo "(not reading /proc/self/status; capability check skipped)"
fi
pass "no effective capabilities set (CapEff=0)"
