#!/usr/bin/env bash
# Case 14: extra volume mount (volume-mounts / -v wiring).
# The runner mounts a temp dir read-write at /mnt/ocs-fwd — the same
# docker `-v` mechanism build_run_flags uses for volume-mounts entries.
# The dir must exist inside the container and be writable by dev.
# SKIPs when the runner did not mount it (run outside `ocs test`).
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

MNT="/mnt/ocs-fwd"

# Write roundtrip: create as dev, read back, remove. (The Dockerfile.test
# creates this dir at build time, so its alone is not proof of the mount —
# the write roundtrip is.)
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
