#!/usr/bin/env bash
# Case 10: resource limits + NoNewPrivs are enforced on the running container
# (host-DoS guard). The run doors add --memory/--cpus/--pids-limit/
# --security-opt=no-new-privileges:true (see build_run_flags in bin/shared);
# the container surfaces them through cgroups, readable by 'dev' here.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

# Detect the visible cgroup layout.
CG=""
if [[ -f /sys/fs/cgroup/memory.max && -f /sys/fs/cgroup/cpu.max ]]; then
  CG="v2"
elif [[ -d /sys/fs/cgroup/memory || -d /sys/fs/cgroup/pids ]]; then
  CG="v1"
else
  echo "SKIP: no cgroup v1/v2 hierarchy visible inside the container"
  exit 0
fi

if [[ "${CG}" == "v2" ]]; then
  mem_max="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
  cpu_max="$(awk '{print $1}' /sys/fs/cgroup/cpu.max 2>/dev/null || true)"
  pids_max="$(cat /sys/fs/cgroup/pids.max 2>/dev/null || true)"
else
  mem_max="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true)"
  cpu_max="$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || true)"
  pids_max="$(cat /sys/fs/cgroup/pids/pids.max 2>/dev/null || true)"
fi

echo "cgroup${CG}: memory.max=${mem_max:-?} cpu.max=${cpu_max:-?} pids.max=${pids_max:-?}"

# Memory must be a finite byte count ("max" = unlimited = fail).
if ! [[ "${mem_max}" =~ ^[0-9]+$ ]]; then
  fail "memory limit not set (memory.max='${mem_max:-missing}')"
fi

# CPU: v2 reports "max" and v1 reports "-1" or empty when unlimited.
if [[ -z "${cpu_max}" || "${cpu_max}" == "max" || "${cpu_max}" == "-1" ]]; then
  fail "CPU limit not set (cpu.max='${cpu_max:-missing}')"
fi

# Pids: finite number or the agent can fork-bomb the host.
if ! [[ "${pids_max}" =~ ^[0-9]+$ ]]; then
  fail "pids limit not set (pids.max='${pids_max:-missing}')"
fi

# NoNewPrivs must be 1 for the current process (setuid escalation guard).
nnp="$(awk '/^NoNewPrivs:/{print $2}' /proc/self/status 2>/dev/null)"
if [[ "${nnp}" != "1" ]]; then
  fail "NoNewPrivs not set (NoNewPrivs=${nnp:-missing})"
fi

pass "memory=${mem_max}, cpu=${cpu_max}, pids=${pids_max}, NoNewPrivs=1 (host-DoS guards active)"
