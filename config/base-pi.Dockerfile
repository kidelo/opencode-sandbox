# ==========================================================================
# base-pi.Dockerfile — precompiled "full pi" base (ocs-base-pi).
#
# NOT a selectable profile (name does not match the Dockerfile.* glob).
# `ocs rebuild` builds it into the local image `ocs-base-pi` BEFORE a
# `pi-full` profile build. It inherits EVERYTHING expensive that pi needs from
# `ocs-base-full` (the full dev toolchain apt set + the large pip data/office/
# PDF/OCR/sci stack + the community LSP plugin bake), so this file does NOT
# re-run any of that — it only adds the pi-specific bake: the prebuilt Node.js
# toolchain + the pi-agent managed tree. (models.json is per-project, baked by
# the pi-full tail from the `pi-base-url:` build arg.)
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
# instead of on every project). The official "linux-x64" tarball is the plain
# glibc build (the musl variants are separate `-musl` files; a
# "linux-x64-glibc.tar.gz" URL 404s). The binary bundles npm/npx — no separate
# install needed.
ARG NODE_VERSION="v24.22.3"
RUN set -e ; \
    NODE_DIST="node-${NODE_VERSION}-linux-x64.tar.gz" ; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}" \
    | tar -xzf - -C /usr/local --strip-components=1 \
    && ln -sf /usr/local/bin/node /usr/local/bin/pi-node \
    && chmod +x /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
    && rm -rf /var/cache/apt/archives/*

# --- pi-agent managed tree (baked, pinned; models.json is per-project) -----
# Same managed recipe as base-pi-minimal: the pi CLI (installed to the
# explicit global prefix via `--prefix`) + the extra plugin (pi-subagents).
# models.json (which points the ollama provider at the project's intranet
# endpoint) is baked by the pi-full tail from the PI_BASE_URL build arg, so
# the base stays host-shared.
ARG PI_CODING_AGENT_DIR="/opt/ocs/pi-agent"
RUN set -e ; \
    mkdir -p "${PI_CODING_AGENT_DIR}" \
    && npm install -g --ignore-scripts --prefix "${PI_CODING_AGENT_DIR}" @earendil-works/pi-coding-agent@1.4.0 \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
       "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-subagents@0.89.2 \
    && chown -R "${USER_ID}:${GROUP_ID}" "${PI_CODING_AGENT_DIR}"

# --- pi-lens extension (built-in LSP) ---------------------------------------
# Same extension as base-pi-minimal (see there). In this chain
# pyright-langserver comes from the pip pyright package (the full toolchain —
# the `command -v` guard makes the bake FAIL if it is ever absent: the server
# is part of the pi engine's built-in LSP surface). pi-lens auto-detects the
# server with zero config (its own global config lives in ~/.pi-lens/).
# context-mode (npm:context-mode) is baked in alongside pi-lens — the
# context-window saver (FTS5 search, sandboxed code execution, session
# continuity). It lists `pi` as a first-class target and has no external
# runtime deps, so it works fully offline.
# pi-memory (npm:pi-memory, the memory_search tool) is NOT baked here either:
# its runtime backend (qmd) needs 3 GGUF models the offline pi base cannot
# fetch at runtime, so it is dropped to keep the bake lean.
RUN set -e ; \
    command -v pyright-langserver \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
        "${PI_CODING_AGENT_DIR}/bin/pi" install npm:pi-lens@4.5.1 \
    && PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR}" \
        "${PI_CODING_AGENT_DIR}/bin/pi" install npm:context-mode \
    && chown -R "${USER_ID}:${GROUP_ID}" "${PI_CODING_AGENT_DIR}"

WORKDIR ${WORKSPACE_DIR}
