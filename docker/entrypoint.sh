#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Read-only rootfs + tmpfs note. Every door runs with `--read-only` plus a sized
# tmpfs map (see build_run_flags in bin/shared), so the overlay image is
# immutable at runtime and temp/home writes are memory-bounded. The bounding
# capability set is deliberately {NET_ADMIN,SETUID,SETGID} — NO CAP_CHOWN — and
# Docker's --tmpfs has no uid/gid option, so this entrypoint chowns nothing.
# The dirs the unprivileged users write are mounted mode=1777 (sticky
# world-writable): dev creates its own ~/.cache|.config and ~/.local/state; the
# opencode state bind at ~/.local/share/opencode stays untouched (never recurse
# a chown into ~/.local — that path can sit over host files). squid needs no
# proxy-owned dir: docker/squid.conf uses `pid_filename none`.
# ---------------------------------------------------------------------------

# --- Egress audit (opt-in, `egress-audit: on`) -------------------------------
# When active, squid runs with a config copied into the /run tmpfs with the
# access_log redirected to /run/squid-access.log (bounded by the 64m /run
# tmpfs, so the log cannot exhaust disk and disappears with the container).
# The rootfs is read-only, so we cannot sed the baked config in place; the /run
# copy is the only viable path. The copy is world-readable 0644: any user may
# read the log, but it only contains URLs the proxy forwarded, which are
# already on the whitelisted domains the agent was allowed to hit.
# ---------------------------------------------------------------------------
_SQUID_CONF=/etc/squid/squid.conf
_EGRESS_AUDIT="$(tr -d '[:space:]' < /etc/egress-audit 2>/dev/null || echo off)"
if [[ "${_EGRESS_AUDIT}" == "on" ]]; then
  _SQUID_CONF=/run/squid.conf
  cp /etc/squid/squid.conf "${_SQUID_CONF}"
  chmod 0644 "${_SQUID_CONF}"
  sed -i 's|^access_log none|access_log /run/squid-access.log squid|' "${_SQUID_CONF}"
  echo ">> egress-audit ON (squid -> /run/squid-access.log, bounded by /run tmpfs)"
else
  echo ">> egress-audit OFF (default)"
fi

# ---------------------------------------------------------------------------
# Proxy: start squid ONLY when outbound domains are whitelisted. With an empty
# http-domain-whitelist there is no external server the agent needs to reach,
# so we skip squid entirely (no squid process, no proxy env); the firewall
# below still default-denies all other egress. Note: the SETUID/SETGID caps are
# granted UNCONDITIONALLY by the host (see compute_cap_flags in bin/shared)
# because every door drops root -> dev via gosu, which needs them regardless of
# whether squid runs.
# ---------------------------------------------------------------------------
if [[ -s /etc/squid/squid-whitelist.txt ]]; then
  echo ">> starting squid proxy (squid startup messages below are expected)"
  squid -c "${_SQUID_CONF}"
  timeout 30 bash -c 'until curl --silent --output /dev/null --max-time 1 http://127.0.0.1:3128; do sleep 0.2; done'
  echo ">> squid is ready"
else
  echo ">> no http-domain-whitelist -> skipping squid proxy (firewall-only egress)"
fi

# ---------------------------------------------------------------------------
# Firewall: default-deny outbound traffic. Allow only what is required:
# - loopback traffic (OpenCode -> local squid)
# - established/related packets
# - squid process (proxy user) DNS + HTTP/HTTPS to the internet
# - host TCP ports listed in /etc/host-ports.txt
# ---------------------------------------------------------------------------
echo ">> configuring firewall"
# Flush existing OUTPUT rules to avoid duplicates on container restart
iptables  -F OUTPUT
ip6tables -F OUTPUT
# Note: ip6tables is run unconditionally. On kernels without IPv6 support this will
# fail and abort startup. We accept this risk to keep the setup simple.

# Default-deny outbound for both IPv4 and IPv6
iptables  -P OUTPUT DROP
ip6tables -P OUTPUT DROP

# ---------------------------------------------------------------------------
# DNS-tunnel mitigation: the AGENT (dev uid) must not be able to use Docker's
# built-in resolver (127.0.0.11:53) as an exfil/C2 channel (DNS-tunnelling).
#
# Mechanism (verified in this project — see moby/moby#40515):
#   Filter-table `-m owner --uid-owner <dev>` does NOT match DNS packets to
#   127.0.0.11; the socket-owner context for that path is dockerd's resolver
#   socket, not the sending agent's socket. So a filter-table DROP rule is
#   useless here even when placed before `-o lo ACCEPT`.
#   The nat-table, on the other hand, IS traversed for 127.0.0.11 traffic
#   (Docker's own DOCKER_OUTPUT DNAT lives there), and its `-m owner` match
#   DOES match the sending socket's uid. So we install our drop-equivalent
#   in the nat table at the position where Docker already operates.
#
# We use "DNAT to 127.0.0.1:1" (UDP+TCP, v4) as the drop-equivalent: for the
# agent's uid, all :53 egress to 127.0.0.11 is redirected to a dead local
# socket — effectively a black-hole (no listener, no error visible to the
# sender beyond timeout). The rule is scoped to the dev uid, so squid
# (proxy uid) keeps its resolver access for whitelisted domains. IPv6 :53
# (rarely used by the embedded resolver) is covered by the filter-table rules
# below as a defence-in-depth belt.
# Disabled by 'agent-dns: allow' in the project config (needed ONLY when an
# endpoint is a hostname, e.g. the model baseURL).
# ---------------------------------------------------------------------------
AGENT_DNS="$(tr -d '[:space:]' < /etc/agent-dns 2>/dev/null || echo deny)"
if [[ "${AGENT_DNS}" != "allow" ]]; then
  DEV_UID="$(id -u dev)"
  # Primary: nat-table, insert at the FRONT so we intercept before Docker's
  # DOCKER_OUTPUT DNAT. Scoped to dev uid only. (Use DNAT-to-dead because
  # iptables v1.8.9's nft backend refuses DROP in the nat table.)
  iptables   -t nat -I OUTPUT 1 -d 127.0.0.11 -p udp --dport 53 -m owner --uid-owner "${DEV_UID}" -j DNAT --to-destination 127.0.0.1:1
  iptables   -t nat -I OUTPUT 2 -d 127.0.0.11 -p tcp --dport 53 -m owner --uid-owner "${DEV_UID}" -j DNAT --to-destination 127.0.0.1:1
  # IPv6 — Docker's embedded DNS is IPv4-only (127.0.0.11), but cover ::1
  # as defence-in-depth.
  ip6tables  -t nat -I OUTPUT 1 -d ::1 -p udp --dport 53 -m owner --uid-owner "${DEV_UID}" -j DNAT --to-destination ::1%lo:1 2>/dev/null || true
  ip6tables  -t nat -I OUTPUT 2 -d ::1 -p tcp --dport 53 -m owner --uid-owner "${DEV_UID}" -j DNAT --to-destination ::1%lo:1 2>/dev/null || true
  # Secondary (defence-in-depth, harmless if the nat rule already catches it):
  iptables   -A OUTPUT -m owner --uid-owner "${DEV_UID}" -p udp --dport 53 -j DROP
  iptables   -A OUTPUT -m owner --uid-owner "${DEV_UID}" -p tcp --dport 53 -j DROP
  ip6tables  -A OUTPUT -m owner --uid-owner "${DEV_UID}" -p udp --dport 53 -j DROP
  ip6tables  -A OUTPUT -m owner --uid-owner "${DEV_UID}" -p tcp --dport 53 -j DROP
  echo ">> agent-DNS tunnel BLOCKED (dev uid ${DEV_UID} :53 to 127.0.0.11 black-holed via nat-table; filter-table DROP as backup)"
else
  echo ">> agent-DNS tunnel OPEN (agent-dns: allow — explicit config choice)"
fi

# ---------------------------------------------------------------------------
# QUIC / DoT / DoH hardening (defence-in-depth, applied UNCONDITIONALLY).
# The dev uid has no legitimate QUIC (HTTP/3 over UDP:443), DNS-over-TLS
# (UDP/TCP:853) or DNS-over-HTTPS (TCP:8853) need. These are the classic
# "slips past a TCP:443-only allowlist" exfil channels — an explicit per-UID
# DROP here makes the intent visible in `iptables -S` and survives even if a
# future config accidentally adds a broad ACCEPT. Squid's proxy uid is the
# only dev-facing egress and it uses plain TCP:443, so it is unaffected.
# Independent of the agent-dns gate above (works in both modes).
# ---------------------------------------------------------------------------
_DEV_UID="$(id -u dev)"
for _dport in 443 853; do
  iptables   -A OUTPUT -m owner --uid-owner "${_DEV_UID}" -p udp --dport "${_dport}" -j DROP
  ip6tables   -A OUTPUT -m owner --uid-owner "${_DEV_UID}" -p udp --dport "${_dport}" -j DROP 2>/dev/null || true
done
for _dport in 853 8853; do
  iptables   -A OUTPUT -m owner --uid-owner "${_DEV_UID}" -p tcp --dport "${_dport}" -j DROP
  ip6tables   -A OUTPUT -m owner --uid-owner "${_DEV_UID}" -p tcp --dport "${_dport}" -j DROP 2>/dev/null || true
done
echo ">> QUIC/DoT/DoH BLOCKED for dev uid ${_DEV_UID} (udp:443,udp:853,tcp:853,tcp:8853 — no QUIC/DNS-over-TLS/DNS-over-HTTPS exfil)"

# Allow loopback (needed for proxy connections to squid on 127.0.0.1:3128)
iptables  -A OUTPUT -o lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
# Allow packets that belong to already established connections
iptables  -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow squid process DNS lookups
iptables  -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
iptables  -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT
# Allow squid process outbound HTTP / HTTPS
iptables  -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80  -j ACCEPT
iptables  -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80  -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT

# Allow host TCP ports (databases etc.) — one port number per line in /etc/host-ports.txt.
# Rules target a CONCRETE IP (docker.host resolves to the host gateway) so the
# entrypoint never depends on iptables' own hostname resolution. If docker.host
# is not resolvable in this container (e.g. a helper container started without
# --add-host=docker.host), skip the host-port rules entirely instead of letting
# set -e abort startup.
HOST_IP=$(getent hosts docker.host 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1; exit}' || true)
if [[ -n "${HOST_IP:-}" ]]; then
  while IFS= read -r port || [[ -n "${port:-}" ]]; do
    iptables -A OUTPUT -d "${HOST_IP}" -p tcp --dport "${port}" -j ACCEPT
  done < /etc/host-ports.txt
fi

# Allow intranet ip:port endpoints (bypass the proxy) — one ip:port per line in /etc/intranet-endpoints.txt
INTRANET_IPS=()
while IFS= read -r endpoint || [[ -n "${endpoint:-}" ]]; do
  [[ -z "${endpoint}" ]] && continue
  iptables -A OUTPUT -d "${endpoint%%:*}" -p tcp --dport "${endpoint##*:}" -j ACCEPT
  INTRANET_IPS+=("${endpoint%%:*}")
done < /etc/intranet-endpoints.txt

# ---------------------------------------------------------------------------
# Environment: route outbound traffic through squid — only when squid is
# active (a non-empty whitelist). When it is not active, no_proxy is left
# unset so client tools talk directly (and only the firewall decides egress).
# ---------------------------------------------------------------------------
if [[ -s /etc/squid/squid-whitelist.txt ]]; then
  export http_proxy="http://127.0.0.1:3128"
  export https_proxy="http://127.0.0.1:3128"
  export HTTP_PROXY="http://127.0.0.1:3128"
  export HTTPS_PROXY="http://127.0.0.1:3128"
  _no_proxy_hosts="localhost,127.0.0.1,docker.host"
  [[ -n "${HOST_IP}" ]] && _no_proxy_hosts="${_no_proxy_hosts},${HOST_IP}"
  for _ip in ${INTRANET_IPS[@]+"${INTRANET_IPS[@]}"}; do
    _no_proxy_hosts="${_no_proxy_hosts},${_ip}"
  done
  export no_proxy="${_no_proxy_hosts}"
  export NO_PROXY="${_no_proxy_hosts}"
fi

# ---------------------------------------------------------------------------
# Landlock (opt-in, `landlock: on`): kernel-enforced write boundary on top of
# the other layers (caps drop, ro rootfs, ro mount overlays, seccomp).
# Defence-in-depth: if a capability leak grants write to a ro path, Landlock
# still denies it. Opt-in; skipped silently on kernels without Landlock.
# Must run BEFORE `gosu dev` — it only restricts the current process tree.
# A machine-readable marker (/run/.landlock-<state>) is left for the test
# suite; state is one of {applied, skipped, off, failed}.
# ---------------------------------------------------------------------------
_LANDLOCK="$(tr -d '[:space:]' < /etc/landlock 2>/dev/null || echo off)"
if [[ "${_LANDLOCK}" == "on" ]]; then
  _LL_OUT="$(LL_RW_PATHS="/workspace:/home/dev:/tmp:/run:/var/tmp" python3 /opt/ocs/landlock.py 2>&1 || true)"
  # surface the helper's log
  printf '%s\n' "${_LL_OUT}"
  _LL_STATE="$(printf '%s' "${_LL_OUT}" | grep -oE 'LL_STATE=[a-z]+' | head -n1 | cut -d= -f2 || true)"
  case "${_LL_STATE}" in
    applied)  : > /run/.landlock-applied;  echo ">> landlock marker: /run/.landlock-applied" ;;
    skipped)  : > /run/.landlock-skipped; echo ">> landlock marker: /run/.landlock-skipped (kernel lacks Landlock)" ;;
    *)        : > /run/.landlock-failed;  echo "!! landlock marker: /run/.landlock-failed" ;;
  esac
else
  : > /run/.landlock-off 2>/dev/null || true
  echo ">> landlock OFF (default); marker: /run/.landlock-off"
fi

# ---------------------------------------------------------------------------
# Git hook neutralization (H1) — entrypoint half. The other half is the
# `RUN git config --system core.hooksPath /dev/null` baked into each profile
# (Dockerfile.minimal/.full/.test) — the image's /etc/gitconfig already sets
# the in-container hook path to a null sink, so any in-container `git commit`
# by the agent is a no-op for hook firing. What remains for the entrypoint:
# (a) a belt-and-braces re-assert in case the bake is removed (best-effort,
#     silently skipped on a read-only /etc), and (b) a note that the HOST-
#     SIDE hooks are unaffected (different scope, different fs).
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  # Best-effort (ro rootfs may make this a no-op — the profile bake is the
  # real enforcement).
  if git config --system core.hooksPath >/dev/null 2>&1; then
    echo ">> git hooks neutralized (system core.hooksPath=$(git config --system --get core.hooksPath))"
  else
    echo ">> git hooks neutralization (baked); host-side hooks unaffected either way"
  fi
else
  echo ">> git hooks neutralization SKIPPED (no git binary in this profile)"
fi

# ---------------------------------------------------------------------------
# OpenCode credentials
# ---------------------------------------------------------------------------
OPENCODE_SERVER_PASSWORD=$(cat /opencode-password)
export OPENCODE_SERVER_PASSWORD
: "${OPENCODE_PORT:=4096}"
export OPENCODE_PORT

# ---------------------------------------------------------------------------
# Start OpenCode as the dev user (gosu drops root, env is inherited).
# - OPCODE_CMD set: run that command (used by ocs-interactive / ocs-run, which
#   pin the model themselves), e.g. OPCODE_CMD='opencode' for the interactive TUI.
# - OPCODE_CMD unset: default to the web server (ocs-start-container).
# ---------------------------------------------------------------------------
echo ">> start opencode"
# SC2016: single quotes are intentional — expressions must expand in the dev user's shell, not root's
# shellcheck disable=SC2016
exec gosu dev bash -c '
  : "${WORKSPACE_DIR:?WORKSPACE_DIR is not set — was the container built without the WORKSPACE_DIR build arg?}"
  cd "${WORKSPACE_DIR}"
  if [[ -n "${OPCODE_CMD:-}" ]]; then
    eval "${OPCODE_CMD}"
  else
    exec /usr/local/bin/opencode web --mdns --port "${OPENCODE_PORT:-4096}"
  fi
'
