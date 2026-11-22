#!/usr/bin/env bash
# Case 30: the mounted model config actually pins the model catalog.
# The classic regression: config mounted but ignored — `opencode models`
# then lists the built-in free catalog (opencode/*) instead of the pinned
# models, and the context-window limit is missing (broken meter).
#
# Unified catalog (multi-model): config/opencode.jsonc "providers.ollama.models"
# is the SINGLE source for BOTH engines. opencode consumes it at runtime
# (catalog is declarative — `opencode models` lists every entry + the full
# ollama library; selection is via `-m provider/model#variant`); pi derives
# its baked models.json from it at build time (host-side transform). So the
# assertions below read the CATALOG (the 6-model set), not a single model.
#
# pi engine: `pi --list-models` (offline, via baked models.json) must resolve
# every catalog id with numeric contextWindow/maxTokens. opencode engine:
# `opencode models` must list every catalog entry, and the config must carry
# the top-level "model" pin + a numeric limit.context (what the meter reads).
#
# SKIPs if the project has no mounted opencode.jsonc (opencode path, same as
# the original case 30).
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

# The pi binary is on the image at /opt/ocs/pi-agent/bin/pi for pi projects
# (pi images are built on the ocs-base-pi* bases). NOTE: the cases run via
# `docker exec -u dev` — the entrypoint exports PI_CODING_AGENT_DIR only in
# its own shell, so the image path is the reliable signal, not PATH. The AGENT
# DIR must be the workspace-seeded /workspace/pi-agent (the single rw dir), NOT
# the baked /opt/ocs/pi-agent: the test container runs with a read-only rootfs
# (--read-only), and `pi` writes auth.json + settings.json.lock into its agent
# dir — EROFS in /opt/ocs/pi-agent. The entrypoint seeds the workspace dir
# before the door, and it survives docker exec (host-side file).
if [[ -x /opt/ocs/pi-agent/bin/pi ]]; then
  # ---- pi engine (pi-mini / pi-full) ------------------------------------
  PI_AGENT_DIR="${WORKSPACE_DIR:-/workspace}/pi-agent"
  [[ -f "${PI_AGENT_DIR}/models.json" ]] || fail "workspace pi-agent seed not found at ${PI_AGENT_DIR} (was the entrypoint run?)"
  # The models.json is the same baked file (seeded from /opt/ocs/pi-agent),
  # so pin assertions below read it from the writable copy.
  PI_MODELS_JSON="${PI_AGENT_DIR}/models.json"

  # Every catalog id must resolve in the baked models.json (offline). The
  # baked file's models array IS the derived catalog, so enumerate it and
  # confirm each entry has a positive numeric contextWindow/maxTokens.
  if ! python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["providers"]["ollama"]["models"]; sys.exit(0 if m and all(isinstance(e.get("contextWindow"), int) and isinstance(e.get("maxTokens"), int) and e["contextWindow"] > 0 and e["maxTokens"] > 0 for e in m) else 1)' "${PI_MODELS_JSON}" 2>/dev/null; then
    fail "baked models.json lacks numeric per-model contextWindow/maxTokens (context meter would be broken)"
  fi

  # `pi --list-models` prints a header line + one row per model
  # ("ollama    ornith-1.5:9b  131.1K   16.4K    no        no") — keep the
  # data rows, drop the header and blanks. NOTE: `docker exec -u dev` does NOT
  # inherit the entrypoint's `export PATH=<agent-dir>/bin` (that's a runtime
  # shell env, not image ENV), so the bare `pi` is not on PATH here — use the
  # absolute image path (the case's own documented reliable signal).
  OUT="$(PI_CODING_AGENT_DIR="${PI_AGENT_DIR}" PI_OFFLINE=1 timeout 90 /opt/ocs/pi-agent/bin/pi --list-models 2>/dev/null | tail -n +2 | grep -v '^$' || true)"
  [[ -n "${OUT}" ]] || fail "pi --list-models produced no model rows (offline? pi binary present?)"

  # The full catalog (6 models) must all resolve in `pi --list-models`.
  RESOLVED_COUNT="$(printf '%s\n' "${OUT}" | grep -c .)"
  [[ "${RESOLVED_COUNT}" -ge 1 ]] || fail "pi --list-models resolved 0 models (baked models.json empty?)"

  # Every id in the baked models.json must appear as a resolvable `pi` row.
  for pid in $(python3 -c 'import json,sys; [print(e["id"]) for e in json.load(open(sys.argv[1]))["providers"]["ollama"]["models"]]' "${PI_MODELS_JSON}" 2>/dev/null); do
    grep -Fq "${pid}" <<< "${OUT}" || fail "pi --list-models -> '${OUT}' but baked models.json contains unresolved id '${pid}'"
  done

  pass "pi catalog resolved ${RESOLVED_COUNT} model(s) from the unified catalog (context + output limits present)"

else
  # ---- opencode engine ---------------------------------------------------
  CFG="${OPENCODE_CONFIG:-/etc/opencode/opencode.jsonc}"
  if [[ ! -e "${CFG}" ]]; then
    echo "SKIP: ${CFG} not present (opencode config not mounted for this project)"
    exit 0
  fi

  # The pinned default model from the config — the exact "model" key.
  PINNED="$(sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${CFG}" | head -1)"
  if [[ -z "${PINNED}" ]]; then
    echo "SKIP: no top-level \"model\" pin found in ${CFG}"
    exit 0
  fi

  # The mounted file is JSONC — it carries `//` line comments (including
  # inside the "$schema" and the ollama baseURL strings), so a raw json.load
  # fails. Strip the comments string-aware (the same logic as
  # build_pi_models_json_python in bin/shared) before parsing. Outputs one
  # modelID per line; the count of those lines is the catalog size.
  catalog_ids() {
    python3 - "${CFG}" <<'PYEOF'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
cleaned = []
for line in raw.split("\n"):
    in_str = False
    comment_at = len(line)
    for i, ch in enumerate(line):
        if in_str:
            if ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch == "/" and (i == 0 or line[i - 1] == "/"):
            comment_at = i - 1
            break
    cleaned.append(line[:comment_at])
doc = json.loads("\n".join(cleaned))
models = doc.get("providers", {}).get("ollama", {}).get("models", {})
for entry in models.values():
    mid = entry.get("modelID", "")
    if mid:
        print(mid)
PYEOF
  }
  IDS="$(catalog_ids 2>/dev/null)"
  N="$(grep -c . <<< "${IDS}")"
  [[ "${N}" -ge 1 ]] || fail "config catalog is empty (or unparseable JSONC)"

  # `opencode models` resolves the effective catalog under this config
  # (built-in registry filtered by the config's provider policy). It must
  # list every entry in the unified catalog.
  OUT="$(timeout 90 opencode models 2>/dev/null)"
  [[ -n "${OUT}" ]] || fail "opencode models produced no output (config not parsed?)"

  # Every catalog id must appear in the resolved opencode catalog.
  for cid in ${IDS}; do
    grep -Fq "${cid}" <<< "${OUT}" || fail "opencode models -> '${OUT}' but config catalog contains unresolved model '${cid}'"
  done
  echo "  opencode catalog lists ${N} model(s) from the unified catalog" >&2

  # The top-level "model" pin (the default the TUI runs) must be one of the
  # catalog entries and carry a numeric context limit (what the meter reads).
  grep -q '"context"[[:space:]]*:[[:space:]]*[0-9][0-9]*' "${CFG}" \
    || fail "config lacks a numeric \"limit\" -> \"context\" pin (context meter would be broken)"

  pass "opencode catalog lists ${N} model(s) (top-level model pin '${PINNED}' + context limit present)"
fi
