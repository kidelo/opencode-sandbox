# ==========================================================================
# base-pi-minimal.Dockerfile — precompiled "lean pi" base (ocs-base-pi-minimal).
#
# NOT a selectable profile (name does not match the Dockerfile.* glob).
# `ocs rebuild` builds it into the local image `ocs-base-pi-minimal` BEFORE a
# `pi-mini` profile build, so the expensive parts that are common to the pi
# one-shot door (the Debian base + the common sandbox-harness apt set + the
# dev user + dirs + git-hook neutralization + the xdg-open stub + the baked
# Node.js toolchain + the pi-agent managed tree + models.json) are installed
# ONCE per host and reused by every pi-mini-profile project.
#
# Deliberately INDEPENDENT of ocs-base / ocs-base-full: pi is a separate engine
# (the pi CLI, not opencode) and needs NO opencode CLI. So this base starts
# from the Debian base directly (python:3.13-slim-bookworm) and mirrors only
# the SHARED harness blocks from base.Dockerfile — it SKIPS the opencode-CLI
# download block entirely.
#
# Layers: python:3.13-slim-bookworm <- ocs-base-pi-minimal <- Dockerfile.pi-mini (per-project tail)
#
# Rebuilt automatically when OCS_BASE_API changes (bump in bin/ocs-rebuild-container)
# or the host uid:gid changes (the dev user is baked with them) or the baked
# Node/pi-agent layout changes.
# ==========================================================================

FROM python:3.13-slim-bookworm

ARG USER_ID
ARG GROUP_ID
ARG WORKSPACE_DIR=/workspace

ENV WORKSPACE_DIR=${WORKSPACE_DIR} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- OS packages (the intersection of every profile's set) ----------------
# Mirrors the SHARED apt set from base.Dockerfile: build-essential, curl,
# ca-certificates, git, xdg-utils, gosu, procps, squid, tmux, iptables,
# iproute2, iputils-ping, netcat-openbsd, dnsutils, whois. These are the common
# sandbox-harness packages; pi-mini re-declares nothing else of its own.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        ca-certificates \
        git \
        xdg-utils \
        gosu \
        procps \
        squid \
        tmux \
        iptables \
        iproute2 \
        iputils-ping \
        netcat-openbsd \
        dnsutils \
        whois \
    && rm -rf /var/lib/apt/lists/*

# --- Locales (host-detected, passed as build args by `ocs rebuild`) ----------
ARG OCS_LOCALES="C.UTF-8"
ARG OCS_DEFAULT_LOCALE="C.UTF-8"
RUN needs="" ; \
    for l in ${OCS_LOCALES}; do \
        case "${l}" in C*|POSIX*) ;; *) needs="${needs} ${l}" ;; esac ; \
    done ; \
    if [[ -n "${needs}" ]]; then \
        apt-get update \
            && apt-get install -y --no-install-recommends locales \
            && for l in ${needs}; do printf '%s UTF-8\n' "${l}" >> /etc/locale.gen; done \
            && locale-gen \
            && rm -rf /var/lib/apt/lists/*; \
    fi
ENV LANG=${OCS_DEFAULT_LOCALE}

# --- user / group ----------------------------------------------------------
RUN if ! getent group ${GROUP_ID} > /dev/null 2>&1; then \
    groupadd -g ${GROUP_ID} dev; \
fi
RUN if ! getent passwd ${USER_ID} > /dev/null 2>&1; then \
    useradd -m -l -u ${USER_ID} -g ${GROUP_ID} --shell /bin/bash dev; \
fi

# --- workspace + user dirs ---------------------------------------------------
# /etc/opencode is the (run-time) ro mount point for config/opencode.jsonc.
RUN mkdir -p /etc/opencode
RUN mkdir -p \
        "${WORKSPACE_DIR}" \
        /home/dev/.local \
        /home/dev/.config \
        /home/dev/.cache \
    && chown -R "${USER_ID}:${GROUP_ID}" \
        "${WORKSPACE_DIR}" /home/dev/.local /home/dev/.config /home/dev/.cache

# --- git hook neutralization (H1) --------------------------------------------
# Same system-scope `core.hooksPath /dev/null` bake as base.Dockerfile:
# in-container `git commit`/`add`/`push` never fire planted hooks. The HOST
# -SIDE git is unaffected (different fs scope, different container).
RUN git config --system core.hooksPath /dev/null

# --- headless xdg-open stub --------------------------------------------------
RUN printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open

# --- Node.js + npm prebuilt (lean pi base only) -----------------------------
# pi's engine needs Node.js (>=22.19.0, the bundled `engines.node`). python:3.13
# ships no Node, so install a prebuilt Node + its bundled npm ONCE per host
# here. The official linux-x64 tarball is a musl build that runs fine on the
# glibc host (it resolves glibc libs at runtime); the glibc-specific
# "linux-x64-glibc.tar.gz" variant 404s. The binary bundles npm/npx (no
# separate npm install). NOTE: this is a prebuilt, not a source build.
ARG NODE_VERSION="v24.22.3"
RUN set -e ; \
    NODE_DIST="node-${NODE_VERSION}-linux-x64.tar.gz" ; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}" \
    | tar -xzf - -C /usr/local --strip-components=1 \
    && ln -sf /usr/local/bin/node /usr/local/bin/pi-node \
    && chmod +x /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
    && rm -rf /var/cache/apt/archives/*

# --- pi-agent managed tree + models.json (baked, pinned) --------------------
# `npm install -g --ignore-scripts @earendil-works/pi-coding-agent@1.4.0`
# installs the pi CLI to the explicit global prefix (the `--prefix` flag, NOT
# the NPM_PREFIX env which npm 11 ignores). Then the managed recipe bakes the
# extra plugin (pi-subagents) + writes models.json pointing the ollama provider
# at the intranet endpoint, both REQUIRED for offline use (the container has no
# internet — models.json is what resolves the model without a network fetch).
#
# The template dir must exist BEFORE the global npm install so the managed
# recipe (which writes into it) has a place to write; it is COPY'd into the
# image by the pi-mini/pi-full profiles and baked at the right uid.
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

# --- pi-lsp extension (built-in LSP plugin for the pi engine) ----------------
# pi-lsp (npm:pi-lsp, github.com/Conte777/pi-lsp — "Declarative Pi extension
# for LSP diagnostics and language-server navigation tools") is baked in by
# default: pi-lsp registers LLM tools (lsp_diagnostics, lsp_hover,
# lsp_definition, lsp_references, lsp_symbols) and appends diagnostics to
# write/edit results. The PYRIGHT server (the reference language server of
# the pi-full base — pip package pyright 1.1.414, and here via the npm
# package because the lean pi base has no pip stack) is pre-configured in the
# baked lsp.json below (the GLOBAL config pi-lsp reads — auto-trusted;
# `pi-lsp` config is resolved via PI_AGENT_DIR, which the entrypoint exports
# for the runtime agent dir). In the pi-full chain pyright-langserver is
# already on PATH (see base-pi.Dockerfile) — the `command -v` guard makes
# this RUN a no-op there.
RUN set -e ; \
    command -v pyright-langserver || npm install -g --ignore-scripts pyright@1.1.414 \
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

# --- base reuse labels --------------------------------------------------------
# Stamped by `ocs rebuild` via --label (the single source is OCS_PI_BASE_DEPS in
# bin/ocs-rebuild-container — keep the node@... pin in sync with the
# ARG NODE_VERSION default above; docker labels do not survive `FROM`, so the
# per-project images carry none and the script stamps them at base build).

WORKDIR ${WORKSPACE_DIR}
