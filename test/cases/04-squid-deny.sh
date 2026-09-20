#!/usr/bin/env bash
# Case 04: direct (non-proxy) HTTP to a domain not in the squid whitelist
# shellcheck source=/dev/null
# must fail (Squid 403 or connection failure).
. "$(dirname "$0")/../common.sh"

# Pick a well-known non-whitelisted domain. If it happens to be whitelisted in
# this project's squid-whitelist.txt, skip rather than fail.
target_domain="example.com"
if grep -E '^(\.?)example\.com$' /etc/squid/squid-whitelist.txt >/dev/null 2>&1; then
  echo "SKIP: ${target_domain} is in this project's whitelist"
  exit 0
fi

code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
  -x http://127.0.0.1:3128 "http://${target_domain}/" 2>/dev/null)" || code=000

# 4xx/5xx from squid (not 2xx) means the proxy denied it — which is exactly
# what we want. A 2xx would mean it leaked through.
case "${code}" in
  4*|5*) pass "proxy denied ${target_domain} (HTTP ${code})" ;;
  2*|3*) fail "proxy served ${target_domain} (HTTP ${code}) — not whitelisted" ;;
  000)   pass "connection to proxy for ${target_domain} failed (no egress)" ;;
  *)     fail "unexpected HTTP status ${code} for non-whitelisted ${target_domain}" ;;
esac
