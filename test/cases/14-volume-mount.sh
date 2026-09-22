#!/usr/bin/env bash
# Case 14: extra volume mount (volume-mounts / -v wiring).
# The runner mounts a temp dir read-write at /mnt/ocs-fwd — the same
# docker `-v` mechanism build_run_flags uses for volume-mounts entries.
# Because Dockerfile.test ALSO pre-creates a writable /mnt/ocs-fwd inside
# the image (so the case passes even without a mount — i.e. a bare
# "dir exists" assertion would false-pass), the case asserts that the
# runner's sentinel file is visible in the mount dir and its content
# matches FWD_TEST_SENTINEL. The write roundtrip below is a secondary
# sanity check (dev can write/delete in both directions).
# SKIPs when the runner did not mount it (run outside `ocs test`).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

MNT="/mnt/ocs-fwd"

# If the runner is active (it set FWD_TEST_SENTINEL), a missing sentinel
# file means the -v wiring is broken → FAIL (not SKIP).
# If the runner is not active (manual run outside `ocs test`), SKIP.
expected_sentinel="${FWD_TEST_SENTINEL:-}"
if [[ -z "${expected_sentinel}" ]]; then
  echo "SKIP: FWD_TEST_SENTINEL not set (runner not active; run inside \`ocs test\`)"
  exit 0
fi

sentinel_file="${MNT}/.ocs-fwd-sentinel"
if ! [[ -r "${sentinel_file}" ]]; then
  fail "sentinel ${sentinel_file} not found — the runner's temp dir is not mounted at ${MNT} (-v wiring broken)"
fi
sentinel_content="$(cat "${sentinel_file}" 2>/dev/null)"
if [[ "${sentinel_content}" != "${expected_sentinel}" ]]; then
  fail "sentinel in ${sentinel_file} is '${sentinel_content:-<empty>}' but expected '${expected_sentinel}' — the mounted dir is not the runner's temp dir"
fi

# Write roundtrip: create as dev, read back, remove. (Confirms the mount is
# writable by dev in both directions, on top of the sentinel proof above.)
probe="${MNT}/.ocs-fwd-probe-$$"
if ! printf 'ocs-fwd-ok\n' > "${probe}" 2>/dev/null; then
  # Absent dir and/or not writable — the mount is missing.
  echo "SKIP: ${MNT} not present or not writable (runner did not mount it)"
  exit 0
fi
content="$(cat "${probe}" 2>/dev/null)"
rm -f -- "${probe}" 2>/dev/null || true
if [[ "${content}" != "ocs-fwd-ok" ]]; then
  fail "wrote to ${MNT} but read back '${content:-<empty>}' (expected 'ocs-fwd-ok')"
fi
# Probe removed? (proves the dir is the temp mount, not the image's)
if [[ -e "${probe}" ]]; then
  fail "could not remove probe file from ${MNT} (dir is not writable or not the mounted temp dir)"
fi

pass "extra volume mount usable: ${MNT} exists, writable, read-back exact"
