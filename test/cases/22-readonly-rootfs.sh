#!/usr/bin/env bash
# Case 22: read-only rootfs + sized tmpfs map are enforced (in-container
# hardening, H1). build_run_flags adds --read-only and a sized tmpfs over
# /tmp /run /var/{tmp,spool,log,cache} /home/dev, so the overlay image is
# immutable at runtime and temp writes are memory-bounded (by the --memory
# cgroup) instead of host-disk-backed. The explicit rw bind mounts (workspace,
# opencode state under the tmpfs home, the test harness /mnt/ocs-fwd) must
# keep working — this case asserts both halves from the 'dev' user.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

# 1. The container root filesystem must be mounted read-only.
root_opts="$(awk '$2=="/" {print $4}' /proc/mounts 2>/dev/null)"
if [[ ! "${root_opts}" =~ (^|,)ro(,|$) ]]; then
  fail "container rootfs is writable (mount options '${root_opts}' lack 'ro')"
fi

# 2. Writing to the (immutable) image must be rejected.
expect_fail "image write rejected on read-only rootfs" touch /usr/local/ocs-ro-test

# 3. /tmp is a tmpfs with a finite size= (memory-bounded, not host-disk-backed).
tmp_fs="$(awk '$2=="/tmp" {print $3}' /proc/mounts 2>/dev/null)"
tmp_opts="$(awk '$2=="/tmp" {print $4}' /proc/mounts 2>/dev/null)"
if [[ "${tmp_fs}" != "tmpfs" ]]; then
  fail "/tmp is '${tmp_fs:-unmapped}' — expected an ephemeral tmpfs"
fi
tmp_size_k=0
if [[ "${tmp_opts}" =~ (^|,)size=([0-9]+)([kmg])?(,|$) ]]; then
  tmp_size_k="${BASH_REMATCH[2]}"
  case "${BASH_REMATCH[3]}" in
    m) tmp_size_k=$(( tmp_size_k * 1024 )) ;;
    g) tmp_size_k=$(( tmp_size_k * 1048576 )) ;;
  esac
fi
if [[ -z "${tmp_size_k}" || "${tmp_size_k}" -lt 1 ]]; then
  fail "/tmp tmpfs has no finite size= option (options '${tmp_opts}')"
fi

# 4. Writing beyond that size fails (ENOSPC) instead of spilling to host disk.
expect_fail "over-cap /tmp write rejected" dd if=/dev/zero of=/tmp/ocs-over-cap.bin bs=1024 count=$(( tmp_size_k + 1024 )) status=none
rm -f /tmp/ocs-over-cap.bin 2>/dev/null || true

# 5. The tmpfs home: dev owns no dir a priori (no CAP_CHOWN, so the entrypoint
#    creates/chowns nothing), but /home/dev is world-writable sticky, so dev can
#    create its XDG dirs — including ~/.local/state, which lives in a nested
#    tmpfs because the state BIND at ~/.local/share/opencode makes .local/share
#    root-owned. The bind itself (mount precedence of -v inside --tmpfs) must
#    stay reachable and writable.
for d in /home/dev/.cache /home/dev/.config /home/dev/.local/state; do
  if ! mkdir -p "${d}" 2>/dev/null || [[ ! -w "${d}" ]]; then
    fail "dev cannot create a writable ${d} under the tmpfs home"
  fi
done
if [[ -z "$(awk '$2=="/home/dev/.local/share/opencode" {print $3}' /proc/mounts 2>/dev/null)" ]]; then
  fail "opencode state bind missing under tmpfs /home/dev (mount precedence?)"
fi
marker="/home/dev/.local/share/opencode/.ocs-ro-t-$$"
if ! touch "${marker}" 2>/dev/null; then
  fail "opencode state bind not writable by dev under tmpfs /home/dev"
fi
rm -f "${marker}"

# 6. The workspace (the single user rw dir) must still be writable.
ws_marker="${WORKSPACE_DIR}/.ocs-ro-t-$$"
if ! touch "${ws_marker}" 2>/dev/null; then
  fail "workspace no longer writable under read-only rootfs"
fi
rm -f "${ws_marker}" 2>/dev/null || true

# 7. mode=1777 (sticky world-writable) is the CAP_CHOWN-free ownership
#    mechanism that replaces the old entrypoint chown-fixup — assert it on the
#    tmpfs dirs the unprivileged users write. Check the directory permission
#    bits (stat), NOT /proc/mounts: 1777 is the tmpfs default, so the kernel
#    omits `mode=1777` from the mount options and only echoes a non-default mode.
for d in /tmp /run /home/dev /home/dev/.local; do
  mode="$(stat -c '%a' "${d}" 2>/dev/null || true)"
  if [[ "${mode}" != "1777" ]]; then
    fail "tmpfs ${d} perms are '${mode:-?}' (expected 1777) — CAP_CHOWN-free ownership broken"
  fi
done

pass "rootfs read-only (${root_opts}), /tmp tmpfs size=${tmp_size_k}k, tmpfs dirs 1777 writable by dev, workspace+state rw as dev"