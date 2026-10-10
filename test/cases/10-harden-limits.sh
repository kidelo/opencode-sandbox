#!/usr/bin/env bash
# Case 10: resource limits + NoNewPrivs are enforced on the running container
# (host-DoS guard). The run doors add --memory/--cpus/--pids-limit/
# --ulimit=fsize=<bytes>/--security-opt=no-new-privileges:true (see
# build_run_flags in bin/shared); cgroups + /proc/self/limits expose them,
# readable by 'dev' here.
#
# When the user configured the per-project policy keys (memory:/cpus:/pids:/
# disk: in opencode-sandbox-config.yaml, see "Per-project policy" in README),
# the ocs-test runner forwards the values as POLICY_MEMORY / POLICY_CPUS /
# POLICY_PIDS / POLICY_DISK env vars into the test container. In that case this
# case asserts the *exact* value (not merely that it is finite).
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

# Convert "Nk" / "Nm" / "Ng" (the shape accepted by ocs-rebuild-container)
# into a byte count using pure bash integer arithmetic.
# 1024^0 / 1024^1 / 1024^2 / 1024^3 = 1 / 1024 / 1048576 / 1073741824
mem_to_bytes() {
  # Input shape is validated at rebuild time: ^[0-9]+[kmg]$.
  local v="${1%[kmg]}"
  local suffix="${1:${#v}}"
  case "${suffix}" in
    k) echo $(( v * 1024 )) ;;
    m) echo $(( v * 1048576 )) ;;
    g) echo $(( v * 1073741824 )) ;;
    *) echo "${v}" ;;
  esac
}

# Convert cpus (e.g. "2.0" or "0.5") to a CFS quota in microseconds.
# CFS granularity: 1 CPU = 100000 µs of quota per period.
cpus_to_quota() {
  awk -v c="${1}" 'BEGIN { printf "%d", int(c * 100000) }'
}

if [[ "${CG}" == "v2" ]]; then
  mem_max="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
  # v2 cpu.max is "quota period"; we only need the quota.
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

# File-size limit (RLIMIT_FSIZE): caps the size of a SINGLE file, so a runaway
# agent cannot fill the host filesystem with one giant file. /proc/self/limits
# reports it in bytes (v1/v2 independent).
fsize_max="$(awk '/^Max file size/{print $4}' /proc/self/limits 2>/dev/null || true)"
if [[ -z "${fsize_max}" || "${fsize_max}" == "unlimited" ]]; then
  fail "file-size (fsize) limit not set (Max file size='${fsize_max:-missing}')"
fi

# ---------------------------------------------------------------------------
# Stricter check: if the user set the policy knobs (memory:/cpus:/pids:),
# assert the cgroup values match the configured values exactly. Empty
# POLICY_* vars (no knobs configured) skip the per-key check; the finite
# assertions above still apply.
# ---------------------------------------------------------------------------
if [[ -n "${POLICY_MEMORY:-}" ]]; then
  expected_bytes="$(mem_to_bytes "${POLICY_MEMORY}")"
  if [[ "${mem_max}" != "${expected_bytes}" ]]; then
    fail "memory cgroup=${mem_max} does not match configured 'memory=${POLICY_MEMORY}' (expected bytes=${expected_bytes})"
  fi
fi
if [[ -n "${POLICY_PIDS:-}" ]]; then
  if [[ "${pids_max}" != "${POLICY_PIDS}" ]]; then
    fail "pids cgroup=${pids_max} does not match configured 'pids=${POLICY_PIDS}'"
  fi
fi
if [[ -n "${POLICY_DISK:-}" ]]; then
  expected_fsize="$(mem_to_bytes "${POLICY_DISK}")"
  if [[ "${fsize_max}" != "${expected_fsize}" ]]; then
    fail "fsize limit=${fsize_max} does not match configured 'disk=${POLICY_DISK}' (expected bytes=${expected_fsize})"
  fi
fi
if [[ -n "${POLICY_CPUS:-}" ]]; then
  expected_quota="$(cpus_to_quota "${POLICY_CPUS}")"
  if [[ "${cpu_max}" != "${expected_quota}" ]]; then
    fail "cpu cgroup quota=${cpu_max} does not match configured 'cpus=${POLICY_CPUS}' (expected quota=${expected_quota})"
  fi
fi

if [[ -n "${POLICY_MEMORY:-}${POLICY_PIDS:-}${POLICY_CPUS:-}${POLICY_DISK:-}" ]]; then
  pass "memory=${mem_max}, cpu=${cpu_max}, pids=${pids_max}, fsize=${fsize_max}, NoNewPrivs=1 (host-DoS guards active, configured limits match)"
else
  pass "memory=${mem_max}, cpu=${cpu_max}, pids=${pids_max}, fsize=${fsize_max}, NoNewPrivs=1 (host-DoS guards active)"
fi
