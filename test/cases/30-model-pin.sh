#!/usr/bin/env bash
# Case 30: the mounted opencode config actually pins the model catalog.
# The classic regression: config mounted but ignored — `opencode models`
# then lists the built-in free catalog (opencode/*) instead of the single
# pinned model, and the context-window limit is missing (broken meter).
# This case resolves the catalog the same way the TUI/CLI do and asserts:
#   1. exactly one model is available,
#   2. it is the model the config pins,
#   3. the config carries a numeric context limit (what the meter reads).
# SKIPs if the project has no mounted opencode.jsonc (same as case 17).
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

CFG="${OPENCODE_CONFIG:-/etc/opencode/opencode.jsonc}"
if [[ ! -e "${CFG}" ]]; then
  echo "SKIP: ${CFG} not present (opencode config not mounted for this project)"
  exit 0
fi

# The pinned default model from the config — the exact "model" key
# ("models" is the provider model map and must not match).
PINNED="$(sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${CFG}" | head -1)"
if [[ -z "${PINNED}" ]]; then
  echo "SKIP: no top-level \"model\" pin found in ${CFG}"
  exit 0
fi

# `opencode models` resolves the effective catalog under this config
# (built-in registry filtered by the config's provider policy). It must
# list exactly the pinned model and nothing else.
OUT="$(timeout 90 opencode models 2>/dev/null)"
if [[ -z "${OUT}" ]]; then
  fail "opencode models produced no output (config not parsed?)"
fi

COUNT="$(printf '%s\n' "${OUT}" | grep -c .)"
if [[ "${COUNT}" -ne 1 ]]; then
  fail "expected exactly 1 model, got ${COUNT}: $(printf '%s' "${OUT}" | tr '\n' '; ')"
fi
if [[ "${OUT}" != "${PINNED}" ]]; then
  fail "opencode models -> '${OUT}' but config pins '${PINNED}'"
fi

# The context-window limit pin (what the TUI context meter and compaction
# logic read for the active model) must be present and numeric.
if ! grep -q '"context"[[:space:]]*:[[:space:]]*[0-9][0-9]*' "${CFG}"; then
  fail "config lacks a numeric \"limit\" -> \"context\" pin (context meter would be broken)"
fi

pass "opencode catalog pinned to ${PINNED} (single model, no free catalog, context limit present)"
