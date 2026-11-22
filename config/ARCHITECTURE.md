# Unified model catalog (opencode + pi)

## Single source of truth

`config/opencode.jsonc` -> `providers.ollama.models` is the ONLY place the model
catalog is declared. One edit, both engines follow. Every other location that
previously hardcoded the model list (the pi Dockerfile bakes, the test image
bake, case 30) is now DERIVED from this file at build time.

## The catalog entry shape

```jsonc
"models": {
  "<key>": {
    "name": "Human readable name",
    "modelID": "<ollama canonical id, e.g. ornith-1.5:9b or hf.co/...:tag>",
    "limit": { "context": <int>, "output": <int> }
  }
}
```

- `modelID` is the id used by the ollama server API (`ollama show <id>`).
  It may be `provider/name` or `provider/name#variant` or an ollama `name:tag`.
- `limit.context` / `limit.output` are the per-model context/output token
  caps (what the TUI context meter reads).

## How each engine consumes it

### opencode (runtime)
- The `provider.models` map is **metadata only**. `opencode models` always lists
  the full ollama server library; the map does NOT restrict runtime selection.
- Runtime selection is always via `-m provider/model#variant` (ocs-run/ocs-
  interactive pin it), resolved against the ollama server at request time.
- The map's `name`/`limit` are informational (meter / config display).
- Therefore the opencode engine can list/use ANY of the catalog entries as long
  as the ollama server has that tag — no build bake is needed.

### pi (build time)
- pi resolves models from a baked `models.json` (`providers.ollama.models` =
  an ARRAY of `{id, name, contextWindow, maxTokens}`), NOT from the mounted
  opencode.jsonc (which is a read-only bind mount the pi engine can't read).
- The rebuild transforms the opencode.jsonc catalog into pi's `models.json`
  schema (map -> array; id stripped of `provider/` prefix and `#variant` tail;
  limit.context -> contextWindow; limit.output -> maxTokens) and injects the
  `pi-base-url:` host:port into the baseUrl.
- This bake happens at `ocs rebuild` (and at the `ocs test` rebuild) so the
  catalog stays a single source without a runtime merge.

## Why the transform exists

The two engines use different on-disk schemas and pi needs the models baked at
build time (its container has no runtime internet and can't read the ro
opencode.jsonc mount). Deriving pi's models.json from the opencode.jsonc catalog
at build time keeps ONE config file authoritative.
