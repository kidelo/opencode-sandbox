#!/usr/bin/env bash
# Case 30: the mounted model config actually pins the model catalog.
# The classic regression: config mounted but ignored — `opencode models`
# then lists the built-in free catalog (opencode/*) instead of the single
# pinned model, and the context-window limit is missing (broken meter).
#
# Dual engine (v12+): opencode projects pin via the mounted
# /etc/opencode/opencode.jsonc (same as the original case 30); pi projects
# pin via the baked /opt/ocs/pi-agent/models.json — `pi --list-models` must
# resolve to exactly the baked model, and models.json must carry the
# per-model numeric contextWindow/maxTokens (the pi equivalent of the
# opencode "context meter" pin).
# This case resolves the catalog the same way the TUI/CLI do and asserts:
#   1. exactly one model is available,
#   2. it is the model the config pins,
#   3. the config carries a numeric context limit (what the meter reads).
# SKIPs if the project has no mounted opencode.jsonc (opencode path, same
# as the original case 30).
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

# The pi binary is on the image at /opt/ocs/pi-agent/bin/pi for pi projects
# (pi images are built on the ocs-base-pi* bases). NOTE: the cases run via
# `docker exec -u dev` — the entrypoint exports PI_CODING_AGENT_DIR only in
# its own shell, so the image path is the reliable signal, not PATH.
# The AGENT DIR must be the workspace-seeded /workspace/pi-agent (the single
# rw dir), NOT the baked /opt/ocs/pi-agent: the test container runs with a
# read-only rootfs (--read-only), and `pi` writes auth.json + settings.json.lock
# into its agent dir — EROFS in /opt/ocs/pi-agent. The entrypoint seeds the
# workspace dir before the door, and it survives docker exec (host-side file).
if [[ -x /opt/ocs/pi-agent/bin/pi ]]; then
  # ---- pi engine (pi-mini / pi-full) ------------------------------------
  PI_AGENT_DIR="${WORKSPACE_DIR:-/workspace}/pi-agent"
  [[ -f "${PI_AGENT_DIR}/models.json" ]] || fail "workspace pi-agent seed not found at ${PI_AGENT_DIR} (was the entrypoint run?)"
  # The models.json is the same baked file (seeded from /opt/ocs/pi-agent),
  # so pin assertions below read it from the writable copy.
  PI_MODELS_JSON="${PI_AGENT_DIR}/models.json"

  # Pinned model id = the (single) model entry in the baked models.json.
  PINNED="$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["providers"]["ollama"]["models"]; print(m[0]["id"])' "${PI_MODELS_JSON}" 2>/dev/null || true)"
  [[ -n "${PINNED}" ]] || fail "no model id in ${PI_MODELS_JSON} (was models.json baked?)"

  # `pi --list-models` prints a header line + one row per model
  # ("ollama    ornith-1.5:9b  131.1K   16.4K    no        no") — keep the
  # data rows, drop the header and blanks. NOTE: `docker exec -u dev` does NOT
  # inherit the entrypoint's `export PATH=<agent-dir>/bin` (that's a runtime
  # shell env, not image ENV), so the bare `pi` is not on PATH here — use the
  # absolute image path (the case's own documented reliable signal).
  OUT="$(PI_CODING_AGENT_DIR="${PI_AGENT_DIR}" PI_OFFLINE=1 timeout 90 /opt/ocs/pi-agent/bin/pi --list-models 2>/dev/null | tail -n +2 | grep -v '^$' || true)"
  [[ -n "${OUT}" ]] || fail "pi --list-models produced no model rows (offline? pi binary present?)"

  COUNT="$(printf '%s\n' "${OUT}" | grep -c .)"
  [[ "${COUNT}" -eq 1 ]] || fail "expected exactly 1 model, got ${COUNT}: $(printf '%s\n' "${OUT}" | tr '\n' '; ')"
  grep -Fq "${PINNED}" <<< "${OUT}" || fail "pi --list-models -> '${OUT}' but baked models.json pins '${PINNED}'"

  # The per-model context/max-out entry (what the pi engine uses) must be
  # present and numeric — the pi equivalent of the opencode context pin.
  if ! python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["providers"]["ollama"]["models"]; sys.exit(0 if m and all(isinstance(e.get("contextWindow"), int) and isinstance(e.get("maxTokens"), int) and e["contextWindow"] > 0 and e["maxTokens"] > 0 for e in m) else 1)' "${PI_MODELS_JSON}" 2>/dev/null; then
    fail "baked models.json lacks numeric per-model contextWindow/maxTokens (context meter would be broken)"
  fi

  pass "pi catalog pinned to ${PINNED} (single model, no free catalog, context limit present)"

else
  # ---- opencode engine ---------------------------------------------------
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
  [[ -n "${OUT}" ]] || fail "opencode models produced no output (config not parsed?)"

  COUNT="$(printf '%s\n' "${OUT}" | grep -c .)"
  [[ "${COUNT}" -eq 1 ]] || fail "expected exactly 1 model, got ${COUNT}: $(printf '%s\n' "${OUT}" | tr '\n' '; ')"
  [[ "${OUT}" == "${PINNED}" ]] || fail "opencode models -> '${OUT}' but config pins '${PINNED}'"

  # The context-window limit pin (what the TUI context meter and compaction
  # logic read for the active model) must be present and numeric.
  grep -q '"context"[[:space:]]*:[[:space:]]*[0-9][0-9]*' "${CFG}" \
    || fail "config lacks a numeric \"limit\" -> \"context\" pin (context meter would be broken)"

  pass "opencode catalog pinned to ${PINNED} (single model, no free catalog, context limit present)"
fi
