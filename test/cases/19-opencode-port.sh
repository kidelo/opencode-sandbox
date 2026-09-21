#!/usr/bin/env bash
# Case 19: opencode-port is forwarded to the run env.
# build_run_flags (via the run doors) passes the configured opencode-port as
# the PORT the server binds; the runner for `ocs test` injects it as
# OPENCODE_PORT. The case asserts the value reaches the dev process env as a
# valid TCP port (1-65535). The ACTUAL bind is verified by the host in the
# smoke-test routine (OpenCode must answer on 127.0.0.1:PORT) — this case
# covers the env wiring only. SKIPs when the runner did not set it.
# shellcheck source=/dev/null
. "$(dirname "$0")/../common.sh"

skip_if_empty OPENCODE_PORT

p="${OPENCODE_PORT}"
if ! [[ "${p}" =~ ^[1-9][0-9]*$ ]] || (( p > 65535 )); then
  fail "OPENCODE_PORT not a valid TCP port (got '${p}')"
fi

pass "opencode-port forwarded into run env (OPENCODE_PORT=${p})"
