#!/usr/bin/env bash
# Case 27: the squid proxy cannot be used to reach a private/link-local/
# metadata IP by any of the three classic bypasses:
#   (a) IP-literal URL  — http://169.254.169.254/...  (no dstdomain match,
#                        should be denied by the existing `deny all` after
#                        the whitelist)
#   (b) DNS rebinding   — a whitelist name resolving to a private IP
#                        (should be denied by the `dst priv_dst` ACL)
#   (c) metadata / loopback
# This case asserts (a) and (c) by behavior (a live HTTP deny), and (b) by
# inspecting the running squid config for the `acl priv_dst dst ...` + the
# `http_access deny priv_dst` pair (behavioral rebinding would need DNS we
# control — we can't run that in the suite without a custom nameserver).
. "$(dirname "$0")/../common.sh"

WHLIST="/etc/squid/squid-whitelist.txt"
if [[ ! -s "${WHLIST}" ]] || ! pgrep -x squid >/dev/null 2>&1; then
  echo "SKIP: squid inactive (empty whitelist) — the firewall-only egress path is covered by cases 03/12"
  exit 0
fi

deny_via_squid() {
  local target="${1}"
  local code
  code="$(curl -s --max-time 6 -o /dev/null -w '%{http_code}' \
    -x http://127.0.0.1:3128 "http://${target}/" 2>/dev/null || true)"
  case "${code:-000}" in
    2*|3*) return 1 ;;
    *)     return 0 ;;
  esac
}

# (a) IP-literal to the AWS metadata endpoint — must be denied.
if deny_via_squid "169.254.169.254"; then
  echo "  -> 169.254.169.254 (AWS metadata) denied via squid"
else
  fail "squid served AWS metadata 169.254.169.254 — IP-literal bypass of the whitelist"
fi

# (c) IP-literal loopback — must be denied.
if deny_via_squid "127.0.0.11"; then
  echo "  -> 127.0.0.11 (Docker resolver) denied via squid"
else
  fail "squid served 127.0.0.11 (Docker resolver) — loopback IP-literal bypass"
fi

# (b) DNS rebinding guard — the running squid.conf must contain the
#     `acl priv_dst dst <private-ranges>` + `http_access deny priv_dst`
#     pair so a whitelisted name resolving to a private IP is denied. A raw
#     grep for the pattern in the live /etc/squid/squid.conf is enough (we
#     can't run a rebinding test without our own DNS).
if ! grep -q 'acl priv_dst dst' /etc/squid/squid.conf 2>/dev/null; then
  fail "squid.conf does not contain an 'acl priv_dst dst ...' (DNS rebinding guard missing)"
fi
if ! grep -Eq 'http_access deny +priv_dst' /etc/squid/squid.conf 2>/dev/null; then
  fail "squid.conf does not have a 'http_access deny priv_dst' rule (rebinding guard not enforced)"
fi
echo "  -> squid.conf contains the private-range 'dst' ACL (b) — rebinding guarded"

pass "squid bypasses (a) IP-literal, (b) DNS rebinding, (c) metadata/loopback all guarded"
