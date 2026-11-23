# ==========================================================================
# base-pi-minimal.Dockerfile — precompiled "lean pi" base (ocs-base-pi-minimal).
#
# NOT a selectable profile (name does not match the Dockerfile.* glob).
# `ocs rebuild` builds it into the local image `ocs-base-pi-minimal` BEFORE a
# `pi-mini` profile build, so the expensive parts that are common to the pi
# one-shot door (the Debian base + the common sandbox-harness apt set + the
# dev user + dirs + git-hook neutralization + the xdg-open stub + the baked
# Node.js toolchain + the pi-agent managed tree) are installed ONCE per host
# and reused by every pi-mini-profile project. (models.json is NOT baked here
# — it is per-project, written by the pi-mini/pi-full tails from the
# `pi-base-url:` build arg so the base stays host-shared.)
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
# Mirrors the SHARED apt set from base.Dockerfile (build-essential, curl,
# ca-certificates, git, xdg-utils, gosu, procps, squid, tmux, iptables,
# iproute2, iputils-ping, netcat-openbsd, dnsutils, whois) PLUS ripgrep —
# added for parity with pi-full, which already inherits it from ocs-base-full
# (see base-full); base.Dockerfile itself does not install it, so this is the
# deliberate divergence of the independent pi-mini base from the shared set.
# These are the common sandbox-harness packages; pi-mini re-declares nothing
# else of its own.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        ca-certificates \
        git \
        ripgrep \
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
# here. The official "linux-x64" tarball is the plain glibc build (the musl
# variants are separate `-musl` files; a "linux-x64-glibc.tar.gz" URL 404s).
# The binary bundles npm/npx (no separate npm install). NOTE: this is a
# prebuilt, not a source build.
ARG NODE_VERSION="v24.22.3"
RUN set -e ; \
    NODE_DIST="node-${NODE_VERSION}-linux-x64.tar.gz" ; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}" \
    | tar -xzf - -C /usr/local --strip-components=1 \
    && ln -sf /usr/local/bin/node /usr/local/bin/pi-node \
    && chmod +x /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
    && rm -rf /var/cache/apt/archives/*

# --- pi-agent managed tree (baked, pinned; models.json is per-project) -----
# `npm install -g --ignore-scripts @earendil-works/pi-coding-agent@1.4.0`
# installs the pi CLI to the explicit global prefix (the `--prefix` flag, NOT
# the NPM_PREFIX env which npm 11 ignores). Then the managed recipe bakes the
# extra plugin (pi-subagents) — REQUIRED for offline use (the container has no
# internet). models.json (which points the ollama provider at the project's
# intranet endpoint) is baked by the pi-mini/pi-full tails from the
# PI_BASE_URL build arg, so the base stays host-shared.
ARG PI_CODING_AGENT_DIR="/opt/ocs/pi-agent"
RUN set -e ; \
    mkdir -p "${PI_CODING_AGENT_DIR}" \
    && npm install -g --ignore-scripts --prefix "${PI_CODING_AGENT_DIR}" @earendil-works/pi-coding-agent@1.4.0 \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
       "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-subagents@0.89.2 \
    && chown -R "${USER_ID}:${GROUP_ID}" "${PI_CODING_AGENT_DIR}"

# --- pi-lens + pi-memory extensions (built-in LSP + memory plugins) ---------
# pi-lens (npm:pi-lens, apmantza/pi-lens) is baked in by default: it registers
# LLM tools (lsp_diagnostics, lsp_hover, lsp_definition, lsp_references,
# lsp_symbols) and appends diagnostics to write/edit results. It zero-config
# auto-detects the language server (no lsp.json needed — pi-lens reads its own
# global config from ~/.pi-lens/config.json). The PYRIGHT server (the reference
# language server — pip package in the pi-full chain, npm package here because
# the lean pi base has no pip stack) is baked the same way: in the pi-full
# chain pyright-langserver is already on PATH (see base-pi.Dockerfile) — the
# `command -v` guard makes this npm install a no-op there; in the lean base the
# npm package provides it. Note: pi-lens's runtime auto-installs
# (biome/prettier/yamllint, GitHub-release binaries) need internet — the
# container has none at runtime, so they fail gracefully; the core LSP path
# works offline.
# pi-memory (npm:pi-memory) is the memory extension (the agent's persistent
# memory; core tools, no qmd semantic-search backend is baked — the container
# has no internet for it).
RUN set -e ; \
    command -v pyright-langserver || npm install -g --ignore-scripts pyright@1.1.414 \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
        "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-lens@4.5.1 \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
        "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-memory@0.4.2 \
    && chown -R "${USER_ID}:${GROUP_ID}" "${PI_CODING_AGENT_DIR}"

# --- base reuse labels --------------------------------------------------------
# Stamped by `ocs rebuild` via --label (the single source is OCS_PI_BASE_DEPS in
# bin/ocs-rebuild-container — keep the node@... pin in sync with the
# ARG NODE_VERSION default above; docker labels do not survive `FROM`, so the
# per-project images carry none and the script stamps them at base build).

WORKDIR ${WORKSPACE_DIR}
