#!/usr/bin/env python3
"""ocs landlock helper — kernel-enforced write boundary (opt-in).

DEFENCE-IN-DEPTH on top of the other layers (read-only rootfs, capability
drop, ro mount overlays, seccomp, nofile). Its value-add: if a capability
leak (bug, race, exploit) somehow grants write to a read-only image path,
the kernel itself still denies it (Landlock rules are bound to the process
tree and cannot be removed once applied).

Model (allow-list):
  RW  /workspace  /home/dev  /tmp  /run  /var/tmp   (the writable dirs)
  RO  /                                                 (everything else)

i.e. allow read+execute on the whole filesystem, allow write only on the
explicitly rw-mounted paths. Any write to a read-only path is denied.
This is a superset of what the current ro mounts already do — it just
moves the enforcement from "mount permissions" to "LSM" so it survives a
capability leak.

Opt-in: `landlock: on` in opencode-sandbox-config.yaml. Skipped silently
on kernels without Landlock support (>= 5.13 FS); the other layers still
carry the security weight.

Exit codes:
  0  ruleset applied, or no-op (kernel lacks Landlock)
  1  Landlock requested but failed to apply (aborts the container so the
     user's `landlock: on` is not silently ignored)
"""

import ctypes
import ctypes.util
import os
import sys

# Landlock syscall numbers (stable across all archs since kernel 5.13)
SYS_landlock_create_ruleset = 444
SYS_landlock_add_rule       = 445
SYS_landlock_restrict_self  = 446
LANDLOCK_CREATE_RULESET_VERSION = 0x1

# Landlock access bits (include/uapi/linux/landlock.h)
A_READ_FILE   = 1 << 0
A_WRITE_FILE  = 1 << 1
A_EXECUTE     = 1 << 2
A_READ_DIR    = 1 << 3
A_REMOVE_DIR  = 1 << 4
A_REMOVE_FILE = 1 << 5
A_MAKE_CHAR   = 1 << 6
A_MAKE_DIR    = 1 << 7
A_MAKE_REG    = 1 << 8
A_MAKE_SOCK   = 1 << 9
A_MAKE_FIFO   = 1 << 10
A_MAKE_BLOCK  = 1 << 11
A_MAKE_SYM    = 1 << 12
A_REFER       = 1 << 13
A_TRUNCATE    = 1 << 14

FS_ALL = (
    A_READ_FILE | A_WRITE_FILE | A_EXECUTE | A_READ_DIR
    | A_REMOVE_DIR | A_REMOVE_FILE
    | A_MAKE_CHAR | A_MAKE_DIR | A_MAKE_REG | A_MAKE_SOCK
    | A_MAKE_FIFO | A_MAKE_BLOCK | A_MAKE_SYM | A_REFER
    | A_TRUNCATE
)
FS_RO = (
    A_READ_FILE | A_READ_DIR | A_EXECUTE | A_REFER
)

LANDLOCK_RULE_PATH_BENEATH = 1


def _libc():
    name = ctypes.util.find_library("c") or "libc.so.6"
    return ctypes.CDLL(name, use_errno=True)


def _probe(libc) -> int:
    """Return the Landlock ABI version (0 = unsupported)."""
    libc.syscall.restype = ctypes.c_long
    ret = libc.syscall(SYS_landlock_create_ruleset, None, 0,
                       LANDLOCK_CREATE_RULESET_VERSION)
    if ret < 0:
        return 0
    return int(ret)


def _structs(abi):
    if abi >= 4:
        class RulesetAttr(ctypes.Structure):
            _fields_ = [("handled_access_fs", ctypes.c_uint64),
                        ("handled_access_net", ctypes.c_uint64)]
    else:
        class RulesetAttr(ctypes.Structure):
            _fields_ = [("handled_access_fs", ctypes.c_uint64)]
    class PathBeneathAttr(ctypes.Structure):
        _fields_ = [("allowed_access", ctypes.c_uint64),
                    ("parent_fd", ctypes.c_int32)]
    return RulesetAttr, PathBeneathAttr


def apply(rw_paths, ro_paths):
    libc = _libc()
    abi = _probe(libc)
    if abi <= 0:
        raise RuntimeError("landlock_unsupported")
    RulesetAttr, PathBeneathAttr = _structs(abi)

    attr = RulesetAttr()
    attr.handled_access_fs = FS_ALL  # we'll decide on every FS access
    ret = libc.syscall(
        SYS_landlock_create_ruleset,
        ctypes.byref(attr), ctypes.c_size_t(ctypes.sizeof(attr)),
        ctypes.c_uint32(0),
    )
    if ret < 0:
        raise RuntimeError(f"create_ruleset: {ctypes.get_errno()}")
    rs_fd = int(ret)
    try:
        def add(path, allowed):
            if not os.path.isdir(path):
                return
            fd = os.open(path, os.O_PATH | os.O_CLOEXEC)
            if fd < 0:
                return
            try:
                pb = PathBeneathAttr()
                pb.allowed_access = allowed
                pb.parent_fd = fd
                r = libc.syscall(
                    SYS_landlock_add_rule,
                    ctypes.c_int(rs_fd),
                    ctypes.c_int(LANDLOCK_RULE_PATH_BENEATH),
                    ctypes.byref(pb), ctypes.c_uint32(0),
                )
                if r != 0:
                    raise RuntimeError(f"add_rule({path}): {ctypes.get_errno()}")
            finally:
                os.close(fd)

        # RO on / — allow the agent to read/execute EVERYTHING.
        add("/", FS_RO)
        # RW on the writable dirs.
        for p in rw_paths:
            add(p, FS_ALL)

        # no_new_privs (kernel requires it before restrict_self for unprivileged;
        # we have CAP_SYS_ADMIN as root, but set it anyway — it's idempotent).
        libc.prctl.restype = ctypes.c_int
        libc.prctl.argtypes = [ctypes.c_int] * 5
        libc.prctl(38, 1, 0, 0, 0)  # PR_SET_NO_NEW_PRIVS

        ret = libc.syscall(SYS_landlock_restrict_self,
                           ctypes.c_int(rs_fd), ctypes.c_uint32(0))
        if ret != 0:
            raise RuntimeError(f"restrict_self: {ctypes.get_errno()}")
    finally:
        os.close(rs_fd)


def main():
    rw = [p for p in os.environ.get("LL_RW_PATHS", "").split(":") if p]
    ro = [p for p in os.environ.get("LL_RO_PATHS", "").split(":") if p]
    # If the caller passed no explicit allow-list, fall back to the default
    # (broad read + the standard rw dirs).
    if not rw:
        rw = ["/workspace", "/home/dev", "/tmp", "/run", "/var/tmp"]
    try:
        apply(rw, ro)
        # Outcome token so the entrypoint can write a machine-readable marker
        # file that the test suite can assert on.
        print("LL_STATE=applied")
        print(">> landlock APPLIED (kernel write boundary for dev)")
        return 0
    except RuntimeError as e:
        if "unsupported" in str(e):
            print("LL_STATE=skipped")
            print(">> landlock SKIPPED (kernel does not support it — "
                  "other hardening layers still active)")
            return 0
        print("LL_STATE=failed")
        print(f"!! landlock FAILED: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
