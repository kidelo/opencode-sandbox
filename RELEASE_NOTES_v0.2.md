# OpenCode Sandbox v0.2

Second release of the `opencode-sandbox` fork. Adds new inspection and resume
commands, pins the OpenCode CLI for reproducible images, serialises
concurrent `ocs rebuild` invocations, layers precompiled base images under
every profile, and hardens the sandbox — Docker resource limits, an
agent-DNS tunnel gate, and a much wider security test suite.

## Highlights

- **`ocs tui` session resume** — `-c/--continue`, `-s <id>`, `--fork`
- **New inspection helpers** — `ocs status [name]` and `ocs logs [name] [flags]` (read-only, no container needed)
- **Pinned OpenCode CLI (1.18.32)** — every container ships the exact version it was built with, reproducible across hosts and rebuilds
- **Rebuild concurrency guard** — `flock` on `ocs rebuild`; the second concurrent invocation exits 75 with a clear message, so two rebuilds for the same project can no longer race on the shared build dir
- **Precompiled base images** (`ocs-base` + `ocs-base-full`) — the expensive, project-independent work (common apt set, `dev` user, OpenCode CLI download, full-profile toolchain apt + pip) is built once per host and reused by every profile build, so `ocs init`/`ocs rebuild` is seconds on any warmed host regardless of profile
- **Hardened Docker runs** — `--memory=4g --memory-swap=4g --cpus=2.0 --pids-limit=256 --security-opt=no-new-privileges:true` on every door
- **Agent-DNS tunnel gate** (`agent-dns:` config key, default `deny`) — the Docker built-in resolver (`127.0.0.11:53`) is denied to the `dev` uid via a nat-table DNAT-to-dead + filter-table DROP (defence in depth); squid retains its resolver when whitelisted
- **Wider security test suite** — 21 deterministic cases (was 11) covering container-lifecycle limits, two-container L2 isolation, positive egress + adjacent-port contrast, run-wiring sentinel files, intranet-endpoint / host-port allowlists, config-ro, workspace-rw, opencode-port, squid consistency, and sandbox-subnet validation
- **Docs & consistency passes** across README / HOWTO / AGENTS

## What's new in this release

| Area | Highlights |
|---|---|
| **New commands** | `ocs tui <name> -c \| -s ID \| --fork` (resume an aborted session); `ocs status [name]` (read-only container listing); `ocs logs [name] [flags]` (flags pass through to `docker logs`) |
| **Build speed** | Precompiled base images (`config/base.Dockerfile`, `config/base-full.Dockerfile`) — the slow shared layers (apt + pip + OpenCode download) are built once per host and reused; `ocs init` / `ocs rebuild` are a few seconds even for the `full` profile |
| **Reproducibility** | OpenCode CLI pinned to 1.18.32 (was "newest available") via `ARG OPENCODE_BUILD_VERSION` + a version guard in the base image; `OCS_BASE_API` bumped so a stale cache is re-baked on a version change |
| **Build safety** | Concurrent `ocs rebuild` for the same project serialised with `flock`; second invocation exits 75 with a clear message, lock auto-released on process exit |
| **Resource limits** | Host-DoS guard on every door: `--memory=4g --cpus=2.0 --pids-limit=256 --security-opt=no-new-privileges:true`, verified by test case 10 |
| **Isolation** | Per-sandbox dedicated Docker network inside a configurable range (default `10.77.0.0/16`); two-container test case 11 proves L2 separation; RFC1918 CIDR enforced |
| **Agent-DNS gate** | Docker's `127.0.0.11:53` resolver black-holed for the `dev` uid (nat-table + filter-table), squid retains its own; opt-in `agent-dns: allow` for hostname-based endpoints (test 12) |
| **Security suite** | 21 cases: container-lifecycle limits, two-container isolation, positive egress (intranet-endpoint `ip:port` + `host-port`), run-wiring (env + mount sentinel), config-ro, workspace-rw, opencode-port, squid consistency, sandbox-subnet; AI-agent red-team case writes its report to `/tmp`, not the workspace |
| **`ocs clean` / `ocs kill`** | `ocs clean` now actually removes project images (not just networks + state); `ocs kill` remains the host-wide cleanup and still removes both shared base images |
| **`ocs init`** | Next-steps hint only suggests `ocs rebuild` when the build did not already run (no redundant step after an immediate build) |
| **Docs** | README / HOWTO / AGENTS consistency passes; "Changes versus upstream" table covers the new surface |

## Up-coming (next release candidate)

- (none — this release is feature-complete for the 0.2 milestone)

## Upstream relationship

This release does not change the upstream relationship — the fork continues
to harden, not diverge. Upstream at
`github.com/comsysto/opencode-sandbox`, Apache-2.0.

## Known changes since v0.1

**Additions**
- `ocs tui` resume flags (`-c`, `-s`, `--fork`)
- `ocs status` and `ocs logs`
- `ocs init` conditional next-steps hint
- OpenCode CLI version pin
- `flock` concurrency guard on `ocs rebuild`
- Precompiled base images
- Docker resource limits + 2-container isolation test
- Agent-DNS tunnel gate (config + tests)
- Positive-egress / run-wiring / sandbox-subnet test cases (13–21)
- RFC1918 private-range enforcement

**Removals**
- Nothing user-visible; all changes are additive

**Incompatibilities**
- **`ocs rebuild` now takes an exclusive lock.** Two simultaneous invocations
  on the same project: the loser exits 75 (no partial state). This is by
  design — the build dir is now the single shared state and can no longer be
  written concurrently.
- **The OpenCode CLI version inside the container is fixed at 1.18.32**
  (it was "newest available" before). If you relied on a specific feature
  that arrived after 1.18.32, you will now need to bump
  `OPENCODE_BUILD_VERSION` in `bin/ocs-rebuild-container` + bump `OCS_BASE_API`,
  then `ocs rebuild` — this is a one-time step.

## Changelog highlights (per commit, oldest to newest)

```
25d7252 Harden docker runs (memory/cpu/pids limits, no-new-privileges) + two-container isolation test
90d6049 Add agent-DNS tunnel gate (uid-scoped, nat-table) + agent-dns config
72f137f Add test case 12: agent-DNS tunnel gate verification
d8948e0 Add positive-egress and run-wiring security test cases (13-21)
28fd953 Fix four bugs: path-injection, regex-injection, name-validation, trap-cleanup
703ba7c Enforce RFC1918 private range for sandbox network CIDR
e5f43d5 Fix stale security-suite counts in README
e45b300 Correct 'ocs terminal' description in ocs help
9d6554f Anchor ocs-clean artifact regex to the exact project ID
d99c919 Replace eval with a safe $VAR expander in volume-mounts
2949809 ocs-run: reject an empty prompt instead of running an empty session
3773bce Correct web/web-auth descriptions in ocs help
f19514e Preserve the dos-guard limits line in the run log
16ed1a6 ocs clean: actually remove project images
eeaecb0 docs: fix six fact inaccuracies across README / HOWTO / AGENTS
1afa8ca Harmonise sandbox-name validation to a single source of truth
cc89a53 ocs rebuild: strip inline comments from list/map values; guard env-passthrough
961888a docs: note intranet-endpoints octet/port range enforced at rebuild
d8570f4 ocs test case 14: prove the -v mount via a runner-side sentinel file
aa77bbb README: document inline-comment stripping per list/map key
04e63d8 ocs tui: resume the last/aborted session
51d48f7 ocs rebuild: hoist expensive layers into precompiled base images
3656318 fix(ocs test): restore Dockerfile.test layer order, bump TEST_API to 4
80f706c docs: polish wording + add TUI resume to what-changed table
f85c501 ocs rebuild: pin the OpenCode CLI to a version (1.18.32)
578119d ocs status + ocs logs: inspect containers and logs without a door
f710b7a ocs: wire status and logs into the dispatcher
56851c4 ocs init: only hint to ocs rebuild when the build did not run
00659ca docs: document ocs status / ocs logs, the CLI pin, and the rebuild lock
619a063 ocs status + README: fix cosmetic issues
```

## Release metadata

- **Tag:** `RELEASE_V0.2-KIDELO`
- **Base tag:** `RELEASE_V0.1-KIDELO` (ef29c16)
- **Commits in range:** 30
