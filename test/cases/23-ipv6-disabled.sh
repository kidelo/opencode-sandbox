#!/usr/bin/env bash
# Case 23: IPv6 is disabled inside the container (H2). build_run_flags adds
# --sysctl net.ipv6.conf.{all,default}.disable_ipv6=1 to every door, so the
# namespace has no active IPv6 stack / addresses / routes — the whole v6
# egress layer is removed from the attack surface (the entrypoint's ip6tables
# rules stay in place as free defence-in-depth).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

if [[ ! -d /proc/sys/net/ipv6 ]]; then
  echo "SKIP: kernel reports no /proc/sys/net/ipv6 (IPv6 compiled off)"
  exit 0
fi

# `all.disable_ipv6=1` covers every existing interface; `default` covers any
# interface created later. We assert the per-interface copies too, since that
# is what actually gates address assignment.
for key in all lo eth0; do
  val="$(cat "/proc/sys/net/ipv6/conf/${key}/disable_ipv6" 2>/dev/null || true)"
  if [[ "${val}" != "1" ]]; then
    fail "IPv6 not disabled: conf/${key}/disable_ipv6='${val:-unreadable}'"
  fi
done

# No default IPv6 route must exist (the sandbox networks are v4-only).
if ip -6 route show 2>/dev/null | grep -q '^default '; then
  fail "a default IPv6 route exists despite disable_ipv6=1"
fi

pass "IPv6 disabled in-namespace (all/lo/eth0 disable_ipv6=1, no default v6 route)"