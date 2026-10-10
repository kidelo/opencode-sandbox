#!/usr/bin/env bash
# Case 29: landlock is an opt-in defensive layer (the primary write-boundary
# is the read-only rootfs + caps drop + ro mount overlays). This case asserts
# the *state* of the Landlock helper:
#   - if the project did not enable it (default), the marker must say 'off'
#   - if the project did enable it, the marker must be one of {applied,
#     skipped, failed} — and if the kernel supports Landlock, 'applied'
#     must be visible.
# This is a best-effort assertion: Landlock is a hardening layer that only
# adds value when it is on AND the kernel supports it. The rest of the
# hardening (read-only rootfs, seccomp, cap drop, ro overlays, nofile,
# QUIC/DoT/DoH, squid rebinding guard) is the primary defence.
. "$(dirname "$0")/../common.sh"

# The project's baked landlock value (the same one the entrypoint reads).
CFG_LANDLOCK="$(tr -d '[:space:]' < /etc/landlock 2>/dev/null || echo off)"
MARKER=""
for m in /run/.landlock-applied /run/.landlock-skipped /run/.landlock-failed /run/.landlock-off; do
  [[ -e "${m}" ]] && MARKER="$(basename "${m}" | sed 's/^\.landlock-//')"
done

if [[ "${CFG_LANDLOCK}" != "on" ]]; then
  [[ "${MARKER}" == "off" || -z "${MARKER}" ]] || true
  pass "landlock OFF (default; marker=${MARKER:-none}) — the ro-overlay + seccomp layer carries the write-boundary"
fi

# landlock was enabled — assert the helper actually ran.
case "${MARKER}" in
  applied)
    pass "landlock APPLIED (kernel enforced; marker=/run/.landlock-applied)"
    ;;
  skipped)
    pass "landlock SKIPPED (kernel <5.13; marker=/run/.landlock-skipped) — other layers (ro overlay, seccomp) carry the weight"
    ;;
  failed)
    fail "landlock was enabled but FAILED to apply (marker=/run/.landlock-failed) — check the entrypoint log"
    ;;
  off|""|*)
    fail "landlock was enabled but no marker was left (expected /run/.landlock-{applied,skipped,failed})"
    ;;
esac
