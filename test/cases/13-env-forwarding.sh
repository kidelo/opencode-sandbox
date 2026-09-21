#!/usr/bin/env bash
# Case 13: environment forwarding (env-passthrough / static env / -e wiring).
# The runner injects FWD_TEST_SENTINEL (random value) and FWD_TEST_STATIC
# (fixed value) via the same docker `-e` mechanism that build_run_flags uses
# for env-passthrough and static env entries. If both arrive in the dev
# process env with their exact values, the env-forwarding plumbing works.
# SKIPs when the runner did not inject them (e.g. run outside `ocs test`).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

skip_if_empty FWD_TEST_SENTINEL FWD_TEST_STATIC

echo "FWD_TEST_SENTINEL=${FWD_TEST_SENTINEL}"
echo "FWD_TEST_STATIC=${FWD_TEST_STATIC}"

# The runner builds the sentinel as ocs-fwd-<16 hex>; require the exact shape
# so a mangled/empty value fails rather than only a loosely-shaped one.
if ! [[ "${FWD_TEST_SENTINEL}" =~ ^ocs-fwd-[0-9a-f]{16}$ || "${FWD_TEST_SENTINEL}" == "ocs-fwd-static" ]]; then
  fail "FWD_TEST_SENTINEL malformed (got '${FWD_TEST_SENTINEL}') — env forwarding broken"
fi
if [[ "${FWD_TEST_STATIC}" != "ocs-static" ]]; then
  fail "FWD_TEST_STATIC expected 'ocs-static', got '${FWD_TEST_STATIC}'"
fi

pass "env forwarding works: sentinel + static value arrived with exact contents"
