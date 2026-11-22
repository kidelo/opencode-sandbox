# ==========================================================================
# base-pi.Dockerfile — precompiled "full pi" base (ocs-base-pi).
#
# NOT a selectable profile (name does not match the Dockerfile.* glob).
# `ocs rebuild` builds it into the local image `ocs-base-pi` BEFORE a
# `pi-full` profile build. It inherits EVERYTHING expensive that pi needs from
# `ocs-base-full` (the full dev toolchain apt set + the large pip data/office/
# PDF/OCR/sci stack + the community LSP plugin bake), so this file does NOT
# re-run any of that — it only adds the pi-specific bake: the prebuilt Node.js
# toolchain + the pi-agent managed tree + models.json.
#
# Layers: python:3.13-slim-bookworm <- ocs-base <- ocs-base-full <- ocs-base-pi
#          <- Dockerfile.pi-full (per-project tail)
#
# Rebuilt automatically when OCS_BASE_API changes (the script's pi-base reuse
# check stamps ocs-base-pi-upstream-api == OCS_BASE_API on this image, so an
# opencode-base-chain bump re-bakes it) or the host uid:gid changes (the script
# stamps ocs-base-pi-uid/gid from USER_ID/GROUP_ID on top of ocs-base-full's,
# so a host-user change re-bakes it — single source: the script).
# ==========================================================================

FROM ocs-base-full

# USER_ID/GROUP_ID: the dev user already exists in ocs-base-full with these
# IDs. The script stamps the pi-base reuse labels on this image (single source:
# OCS_PI_BASE_DEPS + ocs-base-pi-upstream-api in bin/ocs-rebuild-container);
# labels do not survive `FROM`, so nothing is stamped here itself.
ARG USER_ID
ARG GROUP_ID

# --- Node.js + npm prebuilt (full pi base only) -----------------------------
# Same prebuilt Node install as base-pi-minimal (baked once per host here
# instead of on every project). The official linux-x64 tarball is a musl build
# that runs fine on the glibc host (it resolves glibc libs at runtime); the
# glibc-specific "linux-x64-glibc.tar.gz" variant 404s. The binary bundles
# npm/npx — no separate install needed.
ARG NODE_VERSION="v24.22.3"
RUN set -e ; \
    NODE_DIST="node-${NODE_VERSION}-linux-x64.tar.gz" ; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}" \
    | tar -xzf - -C /usr/local --strip-components=1 \
    && ln -sf /usr/local/bin/node /usr/local/bin/pi-node \
    && chmod +x /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
    && rm -rf /var/cache/apt/archives/*

# --- pi-agent managed tree + models.json (baked, pinned) --------------------
# Same managed recipe as base-pi-minimal: the pi CLI (installed to the explicit
# global prefix via `--prefix`) + the extra plugin (pi-subagents) + models.json
# pointing the ollama provider at the intranet endpoint. REQUIRED for offline
# model resolution (the container has no internet — models.json is what lets
# `pi --print --offline` resolve the model).
ARG PI_CODING_AGENT_DIR="/opt/ocs/pi-agent"
ARG PI_BASE_URL="http://192.168.0.139:11434/v1"
RUN set -e ; \
    mkdir -p "${PI_CODING_AGENT_DIR}" \
    && npm install -g --ignore-scripts --prefix "${PI_CODING_AGENT_DIR}" @earendil-works/pi-coding-agent@1.4.0 \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
       "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-subagents@0.89.2 \
    && printf '%s\n' '{' \
        '  "providers": {' \
        '    "ollama": {' \
        '      "api": "openai-completions", ' \
        '      "baseUrl": "'"${PI_BASE_URL}"'", ' \
        '      "apiKey": "ollama", ' \
        '      "models": [' \
        '        { "id": "ornith-1.5:9b", "name": "Ornith 1.5 9B", "contextWindow": 131072, "maxTokens": 16384 }' \
        '      ]' \
        '    }' \
        '  }' \
        '}' > "${PI_CODING_AGENT_DIR}/models.json" \
    && chown -R "${USER_ID}:${GROUP_ID}" "${PI_CODING_AGENT_DIR}"

# --- pi-lsp extension (built-in LSP plugin, pi-full chain) -------------------
# Same lsp.json as base-pi-minimal (see there). In this chain pyright-langserver
# comes from the pip pyright package (the full toolchain — `command -v` guard
# keeps the RUN a no-op when present; if ever absent, fail the bake — the
# server is part of the pi engine's built-in LSP surface).
RUN set -e ; \
    command -v pyright-langserver \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
        "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-lsp@0.1.8 \
    && printf '%s\n' \
        '{' \
        '  "version": 1,' \
        '  "servers": [' \
        '    {' \
        '      "id": "pyright",' \
        '      "enabled": true,' \
        '      "include": ["**/*.py", "**/*.pyi"],' \
        '      "rootMarkers": ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile", "poetry.lock"],' \
        '      "bin": "pyright-langserver",' \
        '      "args": ["--stdio"],' \
        '      "cwd": "{root}",' \
        '      "languageIdByExtension": { ".py": "python", ".pyi": "python" },' \
        '      "startupTimeoutMs": 45000,' \
        '      "diagnosticsWaitMs": 2000,' \
        '      "initializationOptions": {},' \
        '      "settings": {}' \
        '    }' \
        '  ]' \
        '}' > "${PI_CODING_AGENT_DIR}/lsp.json" \
    && chown -R "${USER_ID}:${GROUP_ID}" "${PI_CODING_AGENT_DIR}"

WORKDIR ${WORKSPACE_DIR}
