#!/usr/bin/env bash
# Case 24: auto-exec / host-side-sensitive paths inside the rw workspace are
# pinned read-only by Docker bind overlays. The agent (dev) has write:allow
# on an rw workspace, so without this overlay it could plant .git/hooks,
# .husky, .vscode, .github/workflows, .devcontainer, or modify .git/config
# to redirect hooks — all of which fire on the HOST later (when the user
# commits, opens VS Code, pushes, or devcontainers-up). The overlay is
# mounted AFTER the broad `-v workspace` (Docker precedence: deeper mount
# added later wins), so /proc/mounts shows each protected path as a
# separate mount with `ro` in its options.
#
# Shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

ws="/workspace"
# The default builtin set in bin/shared plus any user-supplied sensitive-paths
# that exist in this workspace. We don't know what the user added, so we
# probe a fixed candidate list and SKIP if none are present (fresh git repo
# or a non-git workspace both SKIP cleanly).
candidates=(
  ".git/hooks"
  ".git/config"
  ".husky"
  ".vscode"
  ".github/workflows"
  ".devcontainer"
)
existing=()
for c in "${candidates[@]}"; do
  [[ -e "${ws}/${c}" ]] && existing+=("${c}")
done
if [[ ${#existing[@]} -eq 0 ]]; then
  echo "SKIP: no auto-exec / host-side-sensitive paths present in ${ws} (fresh repo or non-git workspace?)"
  exit 0
fi

# For each existing protected path, assert:
#   (a) it is a separate mount (visible in /proc/mounts)
#   (b) its mount options include `ro`
#   (c) a write attempt as dev fails with a non-zero exit
for c in "${existing[@]}"; do
  p="${ws}/${c}"
  # (a) it appears in /proc/mounts
  row="$(awk -v mp="${p}" '$2==mp {print; exit}' /proc/mounts)"
  [[ -n "${row}" ]] || fail "protected path ${p} is not a separate mount (no entry in /proc/mounts)"
  # (b) the options field (column 4) contains the ro flag as its own token
  mnt_opts="$(awk -v mp="${p}" '$2==mp {print $4; exit}' /proc/mounts)"
  if ! tr ',' '\n' <<< "${mnt_opts}" | grep -qx 'ro'; then
    fail "protected path ${p} is NOT read-only (mount options: ${mnt_opts})"
  fi
  # (c) a write as dev fails
  if [[ -d "${p}" ]]; then
    probe="${p}/.ocs-ro-probe-$$"
    if touch "${probe}" 2>/dev/null; then
      rm -f "${probe}" 2>/dev/null || true
      fail "protected dir ${p} IS writable by dev (write should have been EROFS)"
    fi
  else
    # .git/config is a file
    if printf 'x\n' >> "${p}" 2>/dev/null; then
      fail "protected file ${p} IS writable by dev (write should have been EROFS)"
    fi
  fi
done

# The workspace itself must still be rw (the overlays only pin the protected
# sub-paths, everything else under /workspace stays user-writable).
ws_probe="${ws}/.ocs-ro-ws-probe-$$"
printf 'ok\n' > "${ws_probe}" 2>/dev/null || fail "/workspace is no longer writable (overlays too broad?)"
rm -f "${ws_probe}" 2>/dev/null || true

pass "auto-exec paths ro-pinned (${#existing[@]}: ${existing[*]}); workspace still rw"
