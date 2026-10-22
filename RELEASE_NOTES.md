# Release notes

The **living** release document for the `opencode-sandbox` fork.

**Update this file on every push** — newest release on top, one section per
release (see AGENTS.md → "Release notes"). When publishing on GitHub: paste
the newest section into the release body and tag `RELEASE_v<X.Y>-KIDELO`.

Last published GitHub release: `RELEASE_V0.1-KIDELO` (2026-09-20). Releases
v0.2–v0.4 below are local milestones shipped in the repo without GitHub
release tags.

---

## v0.5 — OpenCode 1.x → 2.1.x migration *(this push)*

Every door, the entrypoint, the config, and the base image now run
**OpenCode 2.1.2** (was 1.18.32). OpenCode 2 reworked the CLI surface
(`web`/`attach`/`--mdns`/TUI `--fork` are gone) and the config keys, so all
doors were re-wired and re-verified. The host never needs an OpenCode
install — the container keeps being the only place OpenCode runs.

### Highlights

- **Containers ship OpenCode 2.1.2** — pinned by `OPENCODE_BUILD_VERSION` in
  `bin/ocs-rebuild-container`, installed from the `https://opencode.ai/v2/install`
  endpoint (the V1 installer refuses 2.x by design), with an in-image version
  guard; `OCS_BASE_API` bumped 4→5 so stale pre-migration base caches are
  re-baked once and never stale-reused
- **Role-split auth** — the server reads `OPENCODE_SERVER_PASSWORD`, clients
  present `OPENCODE_PASSWORD` (HTTP Basic, user `opencode`); `ocs terminal`
  now hands the password to the in-container TUI client
- **`ocs tui`** — the full TUI via `opencode --standalone`; resume an
  aborted session with `-c/--continue` or `-s/--session <id>`; the V1
  `--fork` door flag is **gone** (fork inside the TUI / session picker, or
  `opencode run --fork` for automation); the `model:` policy knob is
  **display-only** in the TUI — its model comes from the mounted
  `config/opencode.jsonc`
- **`ocs run`** — `opencode run --standalone -m <model>` (model pinned);
  inline prompt strings or prompt files; extra args pass through
- **`ocs terminal`** — the full TUI's `--server` client (OpenCode 2's
  successor of the removed `attach`) attaches to the running web container
  and shares sessions with the browser client
- **`ocs start` / entrypoint** — `opencode serve --hostname 0.0.0.0 --port`
  (OpenCode 2's foreground server; `--hostname 0.0.0.0` replaces V1's
  `--mdns` for host reachability)
- **`config/opencode.jsonc` re-shaped for V2** — `small_model` → the built-in
  `title` agent; `subagent_depth` → `experimental.subagent_depth`;
  `permission.todowrite` → `experimental.todo`; `provider` → `providers`,
  `npm` → `package`, `options` → `settings`; `enabled_providers: ["ollama"]`
  is still honoured (the model catalog stays locked to ollama)
- **Test suite re-wired for V2** — the red-team case 08 drives `opencode run
  --standalone`; `TEST_API` bumped 6→7 so a stale pre-migration test image
  is *rebuilt*, never reused
- **Docs** — README / HOWTO / AGENTS updated for the new surface (doors, auth,
  config shape, suite count)

### Upgrade steps (one-time, per host)

1. Pull the new code.
2. `ocs rebuild` for each project. The first run re-bakes the shared bases
   once (`ocs-base` and, for `full`-profile projects, `ocs-base-full` — the
   slow one; afterwards rebuilds are the usual thin tail, seconds).
3. The shipped `config/opencode.jsonc` is already V2-shaped. If a project's
   copy of the file **predates this release**, replace it with the repo's
   `config/opencode.jsonc` (keeping your provider endpoint/model) — V1 keys
   (`small_model`, singular `provider`, …) are not V2 shapes.
4. Model pinning: `ocs run` still honors the `model:` policy knob (it pins
   `-m`); `ocs tui` takes its model from the mounted `config/opencode.jsonc`.

### Breaking changes

- **OpenCode 1.18.32 → 2.1.2** in every image — V2 CLI surface (`serve`
  replaces `web`, no `attach`, no `--mdns`, no TUI `--fork`/`--model`).
- **`ocs tui --fork` removed** — resume is still `ocs tui [-c | -s <id>]`;
  forking now happens inside the TUI or via `opencode run --fork`.
- **Auth env semantics** — server doors export `OPENCODE_SERVER_PASSWORD`;
  client doors (terminal) export `OPENCODE_PASSWORD`. Both are still generated
  per rebuild at `ocs rebuild` as before.
- **`opencode.jsonc` key renames** (see Highlights) — the shipped template is
  already migrated; hand-rolled V1 configs must follow the mapping.

### Verification

- `ocs test` (fresh test image after the `TEST_API` bump):
  **28 passed / 0 failed / 1 skipped** — the skip is case 27 (squid-bypass),
  expected with an empty `http-domain-whitelist`; that path is covered by
  cases 03/12 (both pass).
- Red-team agent ran on **OpenCode 2.1.2** inside the sandbox — all 6 escape
  attempts blocked (egress-whitelist, egress-direct, privilege, rootfiles,
  writable-system, secret-read).
- End-to-end `ocs run` on a `full`-profile project with the real model
  (`ollama/qwen3.8:27b`): clean round-trip.
- `shellcheck` clean across `ocs bin/* bin/shared docker/entrypoint.sh`.

### Release metadata (v0.5)

- **Tag (planned):** `RELEASE_V0.5-KIDELO`
- **Base:** `31f7211` (v0.4)
- **Commits in range:** `34c06cb` — 14 files: doors (`ocs-interactive`,
  `ocs-run`, `ocs-terminal`, `ocs-start-container`), entrypoint auth + `serve`,
  `config/opencode.jsonc` V2 shape, `config/base.Dockerfile` installer +
  guard, `bin/ocs-test` `TEST_API` 6→7, `bin/ocs-rebuild-container`
  `OCS_BASE_API` 4→5 + `OPENCODE_BUILD_VERSION=2.1.2`, suite case 08,
  README/HOWTO/AGENTS/`ocs` help.

---

## Previous releases

### v0.4 — extra hardening + test cases 24–29

- **Four opt-in knobs** — `seccomp:` (`on` default — Docker's own default
  profile, never a custom one), `landlock:` (`off` default — kernel-enforced
  write boundary via the baked `/opt/ocs/landlock.py` helper), `egress-audit:`
  (`off` — squid access-log to `/run`), `sensitive-paths:` (list of
  workspace-relative paths)
- **Auto-exec hardening** — QUIC/DoT/DoH drops for the dev uid (udp:443,
  udp:853, tcp:853/tcp:8853); squid `dst`-ACL rebinding guard (loopback +
  RFC1918 + CGNAT + link-local + ULA denied); `git config --system
  core.hooksPath /dev/null` so planted hooks can never fire
- **`sensitive-paths` ro-overlays** — built-in set (`.git/hooks`,
  `.git/config`, `.husky`, `.vscode`, `.github/workflows`, `.devcontainer`)
  plus user entries, mounted read-only *over* the rw workspace at run time
- **6 new test cases (24–29)** — sensitive-path ro, git-hook neutralization,
  `RLIMIT_NOFILE` + `nofile:` match, squid IP-literal/loopback/metadata/
  rebinding denials, seccomp attached, Landlock marker state
- `TEST_API` 5→6

### v0.3 — per-project policy knobs + in-container hardening

- **Seven policy knobs** in `opencode-sandbox-config.yaml`: `cpus`, `memory`,
  `pids`, `disk`, `nofile`, `timeout`, `model` — read from `policy.txt` via
  `read_policy`, enforced per door (`--cpus` / `--memory` / `--memory-swap` /
  `--pids-limit` / `--ulimit=fsize` / `--ulimit=nofile`; `timeout` wraps the
  one-shot doors in `timeout --foreground`)
- **Read-only rootfs + bounded tmpfs + no IPv6** — every door runs
  `--read-only` with a sized tmpfs map (`/tmp:512m`, `/run:64m`,
  `/var/tmp:128m`, `/home/dev:256m`, `/home/dev/.local:128m`, `mode=1777`)
  and `disable_ipv6=1` in-namespace; temp/home writes are memory-bounded,
  never host-disk-backed; the IPv6 egress layer disappears (ip6tables rules
  stay as defence-in-depth). Test cases 22/23
- `TEST_API` 4→5

### v0.2 — inspection, resume, pins, bases (30 commits)

- **New commands / flags** — `ocs tui` session resume (`-c`, `-s <id>`,
  `--fork` on the V1 surface), `ocs status [name]`, `ocs logs [name]
  [flags]`
- **Pinned OpenCode CLI (1.18.32)** — `ARG OPENCODE_BUILD_VERSION` + version
  guard in the base image + `OCS_BASE_API` label check (the pin that v0.5
  now moves forward to 2.1.2)
- **Rebuild concurrency guard** — `flock` on `ocs rebuild`; the loser exits
  75 with a clear message; lock auto-released on exit
- **Precompiled base images** — `ocs-base` + `ocs-base-full`, built once per
  host and reused while their labels (`ocs-base-api`, uid/gid) match; every
  `ocs init`/`ocs rebuild` is seconds regardless of profile
- **Docker resource limits** on every door — `--memory=4g --memory-swap=4g
  --cpus=2.0 --pids-limit=256 --security-opt=no-new-privileges:true`
- **Agent-DNS tunnel gate** — `agent-dns:` key (default `deny`); Docker's
  `127.0.0.11:53` resolver uid-scoped black-hole (nat-table DNAT-to-dead +
  filter-table DROP); squid keeps its own resolver; case 12
- **Security suite widened** — 21 deterministic cases + AI red-team
- `ocs clean` actually removes project images; `ocs init` next-steps hint is
  conditional on the build
- Tag: `RELEASE_V0.2-KIDELO` (local milestone — notes at commit `eac6049`)

### v0.1

- First public release of the fork — `RELEASE_V0.1-KIDELO` (2026-09-20)

---

## Release history

| Release | Theme | Tag |
|---|---|---|
| **v0.5** | **OpenCode 1.x → 2.1.x migration** (doors, entrypoint auth, config shape, base, `TEST_API` 7) | `RELEASE_V0.5-KIDELO` (planned) |
| v0.4 | Extra hardening (seccomp / landlock / egress-audit / sensitive-paths / git-hook sink / squid rebinding) + test cases 24–29 | — (local) |
| v0.3 | Per-project policy knobs + read-only rootfs / sized tmpfs / IPv6-off | — (local) |
| v0.2 | TUI resume, `status`/`logs`, CLI pin, precompiled bases, resource limits, agent-DNS gate, 21-case suite | `RELEASE_V0.2-KIDELO` (local) |
| v0.1 | First public release | `RELEASE_V0.1-KIDELO` (published) |
