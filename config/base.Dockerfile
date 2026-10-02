# ==========================================================================
# base.Dockerfile — precompiled shared base for every sandbox profile.
#
# NOT a selectable profile (name does not match the `Dockerfile.*` glob that
# `ocs init` / `ocs rebuild` enumerate; it is built by `ocs rebuild` as the
# local image `ocs-base`, then every `config/Dockerfile.<profile>` does
# `FROM ocs-base`).
#
# Why it exists: apt + the opencode CLI download + dev-user creation are the
# expensive, project-independent layers. Without this base, `ocs init`/
# `ocs rebuild` re-runs all of them for EVERY project — `full` re-downloads
# opencode, re-creates the user, re-lays down the harness. With this base,
# each project build only runs its own profile-specific apt/pip layers on top
# of a cached base. The base is built once per host (and re-built only when
# its layer set / structure / opencode version or the baked uid/gid changes
# — see the ocs-base-api / ocs-base-uid / ocs-base-gid labels checked in
# `ensure_base_image`).
# It is deliberately profile-neutral: only the OS packages + user + opencode
# that are common to EVERY profile. Profile-specific packages, the squid /
# firewall per-project config, /opencode-password, and the entrypoint stay in
# the `Dockerfile.<profile>` files (they are per-project or profile-specific).
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
# All of these are installed by at least one of the minimal / full / test
# profiles; hoisting them here means a profile no longer re-runs apt for the
# shared set. A profile still re-declares anything it uniquely needs.
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
        iptables \
        iproute2 \
        iputils-ping \
        netcat-openbsd \
        dnsutils \
        whois \
    && rm -rf /var/lib/apt/lists/*

# --- user / group ----------------------------------------------------------
# Baked with the host's uid/gid (passed as build args by `ocs rebuild`). If
# they differ from a previously built base, `ensure_base_image` rebuilds this
# image, so the dev user always matches the active host user.
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

# --- opencode CLI ------------------------------------------------------------
# Pinned to a specific release so the sandbox does not silently track "latest".
# The sandbox depends on specific CLI flags (TUI -c/--continue, -s/--session,
# --fork; ocs run non-interactive mode) that can drift between releases. To
# bump, change the default below *and* the OPENCODE_BUILD_VERSION constant in
# bin/ocs-rebuild-container (single source passed as --build-arg), then bump
# OCS_BASE_API there so a stale cached base image gets re-baked.
ARG OPENCODE_BUILD_VERSION=1.18.32
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path --version "${OPENCODE_BUILD_VERSION}" \
    && cp /root/.opencode/bin/opencode /usr/local/bin/opencode \
    && chown "${USER_ID}:${GROUP_ID}" /usr/local/bin/opencode \
    && chmod a+rx /usr/local/bin/opencode \
    && test "$(opencode --version)" = "${OPENCODE_BUILD_VERSION}"

# --- headless xdg-open stub --------------------------------------------------
RUN printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open

WORKDIR ${WORKSPACE_DIR}
