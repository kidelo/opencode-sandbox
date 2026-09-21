#!/usr/bin/env bash
# Case 20: squid startup is state-consistent with the whitelist.
# The entrypoint starts squid ONLY when /etc/squid/squid-whitelist.txt is
# non-empty (no squid when the project has no outbound domains). This case
# asserts state consistency: the two signals must agree.
# The allow/deny BEHAVIOUR is already covered (case 04 = deny, 12 = allow).
#
# Note: the entrypoint's http_proxy env is set in PID-1's shell and is NOT
# visible to `docker exec -u dev bash ...` (fresh process), so we do NOT
# assert http_proxy — only the running state of the squid process.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

WHLIST="/etc/squid/squid-whitelist.txt"
if [[ -s "${WHLIST}" ]]; then
  domain="$(sed -n '1p' "${WHLIST}" | sed 's/^\.\?//; s/[[:space:]]*$//')"
  echo "whitelist non-empty (first: ${domain:-?})"
  # Squid should be running (started at entrypoint).
  if ! pgrep -x squid >/dev/null 2>&1; then
    fail "whitelist is non-empty but the squid process is not running"
  fi
  pass "squid running, whitelist non-empty (state consistent)"
else
  echo "whitelist empty (or absent)"
  # Squid should NOT be running (entrypoint skipped it). pgrep -x only:
  # -f would match this case's own command line (which contains "squid").
  if pgrep -x squid >/dev/null 2>&1; then
    fail "whitelist is EMPTY but a squid process is running (should be skipped)"
  fi
  pass "no squid with an empty whitelist (firewall-only egress; state consistent)"
fi
