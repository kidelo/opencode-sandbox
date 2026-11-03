# Release notes

The **living** release document for the `opencode-sandbox` fork.

**Update this file on every push** — newest release on top, one section per
release (see AGENTS.md → "Release notes"). When publishing on GitHub: paste
the newest section into the release body and tag `RELEASE_v<X.Y>-KIDELO`.

Last published GitHub releases: `RELEASE_V0.8.1-KIDELO`,
`RELEASE_V0.8-KIDELO`, `RELEASE_V0.7.2-KIDELO` and `RELEASE_V0.7-KIDELO`
(all 2026-11-03); v0.7.1 ships in the v0.7.2 push.
Releases v0.2–v0.6 below are local milestones shipped in the repo without
GitHub release tags.

---

## v0.8.2 — detached TUI: truecolour passes through to the terminal

**Bug fix (v0.8 detached TUI).** Even with the v0.8.1 pane env the TUI's
truecolour output was still being **quantised to 16/256 colours** as it crossed
tmux — the panels and background chrome stayed "no colour". This is the second
half of the truecolour chain.

Root cause: tmux only passes truecolour (`38;2;…`/`48;2;…`) through to the
client if *both* the tmux **server** *and* the tmux **client** are told the
terminal is RGB-capable. The client here is the `tmux attach` process running
inside the container, and `docker exec` forwards **no** environment — so it saw
no `TERM` at all and tmux fell back to the 16-colour `xterm` (confirmed with
`list-clients`: `client_termname = xterm`, no RGB feature).

The fix has **two** mandatory halves, both in `bin/ocs-interactive`:

1. **Client env** — the attach/exec now runs the tmux client with the caller's
   real terminal: `… -e TERM=<your TERM> -e COLORTERM=<your COLORTERM> …`.
   (The pane already got `TERM=xterm-256color COLORTERM=truecolor` from v0.8.1;
   this fixes the *client* side of the channel.)
2. **Server feature** — the server is taught that this terminal is RGB via
   `tmux set -as terminal-features '<TERM>:RGB'`, baked into the long-lived
   container's `OPCODE_CMD` and re-applied on every attach.

Gated by `term_is_truecolor()`: only genuinely RGB-capable terminals get it
(`xterm-256color`, `xterm-direct`, `alacritty`, `kitty`, `wezterm`, `foot*`,
`rxvt-unicode*`, plus an explicit `COLORTERM` of `truecolor`/`TrueColor`/
`24bit`). A bare 16-colour `xterm` is left untouched, so genuinely 16-colour
terminals are not garbled.

### Highlights

- `bin/ocs-interactive`: the detached door now bakes both halves into the
  container's `OPCODE_CMD`:
  `tmux new-session -d -s ocs -e TERM=xterm-256color -e COLORTERM=truecolor …`
  plus `tmux set -as terminal-features 'xterm-256color:RGB'` at start — and
  re-applies both on every `ocs tui --attach`.
- Verified **live end-to-end** on the real detached TUI: the pane stream now
  carries **236 truecolour sequences** (`38;2;…`/`48;2;…`) reaching the
  user's terminal, instead of being quantised to 16/256 colours.
- Isolated A/B (same image, tmux 3.3a): server-feature-only → 0; `-e`-only →
  0; **both halves → truecolour flows through** (proven with a disposable
  gradient pane).

### Breaking changes

None.

### Upgrade steps

- **No rebuild needed.** The detached door is assembled at `docker run` time.
  For an already-running detached container: `ocs tui --stop`, then
  `ocs tui --detach` again so the new `OPCODE_CMD` (with both halves) applies.
- The default one-shot door is unchanged.

### Verification

- Live `ocs tui --detach` → pane env `TERM=xterm-256color COLORTERM=truecolor
  LANG=de_DE.UTF-8`, and the server's `tmux show-options` now lists
  `xterm-256color:RGB`.
- Client attach (with `-e TERM=xterm-256color -e COLORTERM=truecolor`) over the
  pane stream: **236 truecolour sequences** captured in the raw stream
  (`38;2;255;255;255`, `48;2;10;10;10`, …) — previously 0.
- `term_is_truecolor()` gate tested on the three required cases
  (`xterm-256color` w/o COLORTERM → allow; bare `xterm` → deny; COLORTERM set
  → allow).
- `shellcheck ocs bin/* bin/shared docker/entrypoint.sh` → clean

### Release metadata (v0.8.2)

- **Base:** `d8cbcb6`
- **Commits in range:** `bin/ocs-interactive`, `RELEASE_NOTES.md`

---

## v0.8.1 — detached TUI: truecolour under tmux

**Bug fix (v0.8 detached TUI).** Inside tmux the TUI fell back to a
16-colour profile, so its panel/background chrome disappeared. Root cause:
tmux hands a new pane `TERM=screen` (its default), and the TUI's renderer
(openTUI) then picks a 16-colour palette — regardless of the outer
terminal's capabilities.

### Highlights

- `bin/ocs-interactive`: the detached door now starts the session as
  `tmux new-session -d -s ocs -e TERM=xterm-256color -e COLORTERM=truecolor …`,
  so the TUI emits truecolour, which tmux 3.x passes through to a
  truecolour-capable client terminal (verified with `tmux pipe-pane`:
  the pane stream carries `38;2;…`/`48;2;…` sequences)

### Breaking changes

None.

### Upgrade steps

- No rebuild needed (door-side change, applied at `docker run`). If a
  detached container from v0.8 is already running, `ocs tui --stop` once and
  `ocs tui --detach` again so the new session environment applies.

### Verification

- Isolated A/B (same image, tmux 3.3a): pane without the env pair → only
  16-colour SGR; with the pair → the TUI writes truecolour
  (`38;2;92;156;245`, `48;2;10;10;10` …) into the pane (`pipe-pane` capture)
- Confirmed visually by the user on their truecolour terminal
- `shellcheck ocs bin/* bin/shared docker/entrypoint.sh` → clean

### Release metadata (v0.8.1)

- **Base:** `d8cbcb6` (v0.8 + bookkeeping)
- **Commits in range:** `bin/ocs-interactive`, `AGENTS.md`, `README.md`,
  `RELEASE_NOTES.md`
- **Tag (published):** `RELEASE_V0.8.1-KIDELO` (2026-11-03)

---

## v0.8 — detached TUI: leave the terminal, the agent keeps working

**Feature.** `ocs tui` gains an **optional** detached mode: the TUI runs inside a
`tmux` session in a **long-lived** container, so you can *leave the terminal*
(`Ctrl-B D`, or just close it / end the SSH session) and the OpenCode session —
including any **running agent work** — keeps going. `--attach` reconnects from
any terminal later; `--stop` / `--status` manage it. The **default door is
unchanged** (one-shot: `exit` still ends it and removes the container).

Why this shape: the one-shot `ocs tui` runs `opencode --standalone` as the
container's main process, so "no terminal" == "container gone" == "work gone".
In detached mode the door's command starts the TUI **detached in tmux**
(`tmux new-session -d`) and parks the main process on `sleep infinity`: leaving
kills the tmux *client* only, while the tmux *server* (and with it the TUI and
its in-process server) stays alive in the container.

### Highlights

- **`ocs tui` modes** (new flags in `bin/ocs-interactive`):
  - `--detach` — start/reuse the long-lived container (`ocs-<ID>-tui`) and,
    when a TTY is present, attach immediately; with no TTY just start it
  - `--attach` — reconnect the tmux session of the running detached TUI
  - `--stop` — `docker stop` + remove the detached container (the chat history
    stays in the persistent opencode state tree — resume with `--detach -c`)
  - `--status` — print container + tmux state
  - default (no mode) — the classic one-shot door, byte-for-byte the same
    behaviour as before (`-c/--continue`, `-s/--session <id>` unchanged)
- **`tmux` ships in the precompiled base** (`config/base.Dockerfile` apt set),
  so *every* profile (and the test image) has it. `OCS_BASE_API` bumps 6→7 so
  the cached base images are re-baked once (and the base-full rebuild follows).
- **Lifecycle plumbing:** deterministic name `ocs-<ID>-tui` (no `$$`) is
  covered by `ocs clean`'s anchored `-tui` suffix and `ocs kill`'s ocs- prefix;
  `ocs status` lists it; `--detach` is idempotent (second call = "already
  running"); `timeout:` does **not** apply to the long-lived container (like
  `ocs start`); the door reuses `build_run_flags`, so the full hardening set
  (caps, limits, ro rootfs, tmpfs, squid, dedicated network) applies identically
- **Doc sync:** `README.md` (tui section + example block + TOC anchor),
  `AGENTS.md` (surface / naming / base bullets), `ocs help`

### Breaking changes

None — the default `ocs tui` one-shot door is unchanged. Detached mode is opt-in.

### Upgrade steps

- `ocs rebuild` once (re-bakes `ocs-base` / `ocs-base-full` with `tmux`; the
  detached door is assembled at `docker run` time, no other restarts needed).
- Any *existing* detached container from an older image can be left running or
  `ocs tui --stop` + restarted; `ocs clean <name>` / `ocs kill` still remove it.

### Verification

_(from the live runs on Docker 29.9.2, 2026-11-03)_

- `ocs rebuild`: both bases re-baked (api 7, `tmux 3.3a` present in the
  project image), `full` profile built clean
- `ocs tui --detach` with no TTY starts the container and reports the
  attach/stop/status commands; the tmux session `ocs` is up.
- Prompt sent **with zero clients attached** via `tmux send-keys`; the agent
  replied (`Build · Qwen3.8 27B`, `OCS-BG-OK`) while no terminal was attached.
- `ocs tui --attach` (PTY, 8 s) shows the chat; killing that client afterwards
  leaves the tmux session alive.
- `--detach` while running → "Detached TUI is already running".
- `--stop` removes it; `--attach` with none running fails cleanly.
- `ocs tui --detach -c` resumes the last session (chat still present).
- `ocs test` full suite: **28 passed, 0 failed, 1 skipped** (the skip is the
  legitimate case-04: this project whitelists `.example.com`)
- `shellcheck ocs bin/* bin/shared docker/entrypoint.sh` → clean ✅

### Release metadata (v0.8)

- **Base:** `e692074` (v0.7.2 + config)
- **Commits in range:** `config/base.Dockerfile` (tmux), `bin/ocs-rebuild-container`
  (OCS_BASE_API 6→7), `bin/ocs-interactive` (modes), `bin/ocs-clean` (`-tui` suffix),
  `ocs` (help), `AGENTS.md`, `README.md`, `RELEASE_NOTES.md`
- **Tag (published):** `RELEASE_V0.8-KIDELO` (2026-11-03)

---

## v0.7.2 — squid under full hardening

**Bug fix: with a non-empty `http-domain-whitelist`, `ocs start` still died
at container start under the full hardening flag set.** v0.7.1 fixed how
squid is invoked; this fixes the capability set the doors run with.

Symptom (the reported start error): the entrypoint brings squid up in
daemon mode, the parent spawns the worker, the worker exits status 1 five
times, the parent gives up and the container dies:

```text
squid[11]: Squid Parent: (squid-1) process 13 started
squid[11]: Squid Parent: squid-1 process 13 exited with status 1
… (×5)
squid[11]: Exiting due to repeated, frequent failures
```

v0.7.1's smoke run did not hit this because it started squid with lighter
flags (default caps + `NET_ADMIN`); the real doors add
`--cap-drop=ALL` down to `{NET_ADMIN,SETUID,SETGID}`,
`--security-opt=no-new-privileges:true`, and the read-only/tmpfs map —
that combination is what kills the worker.

### Root cause — bisected (Squid 5.7, Docker 29.9.2)

Each variant was run in daemon mode with the *exact* door flag set
(`no-new-privileges` on, read-only rootfs, sized tmpfs) + the caps listed:

| Cap set (always on top of `NET_ADMIN,SETUID,SETGID`) | worker |
|---|---|
| v0.7 / v0.7.1 set | ❌ exits status 1, parent gives up |
| + `CHOWN` | ❌ |
| + `FOWNER` | ❌ |
| + `CHOWN` + `FOWNER` | ❌ |
| + **`DAC_OVERRIDE`** | ✅ starts, binds `127.0.0.1:3128` |
| (unchanged set, `no-new-privileges` OFF) | ✅ |

`CAP_DAC_OVERRIDE` is required **and** sufficient — it only ever acts for
root, *before* the worker's `setuid(proxy)` (a real credential transition
drops all caps with it), so the worker's and the agent's runtime
permissions are unchanged. The baked `/etc/squid/squid.conf` /
`squid-whitelist.txt` staying `root:root 0600` is *intentional* (the agent
cannot read its own egress policy); their modes are not the trigger —
world-readable copies were tested and still failed without the cap.

### Highlights

- `compute_cap_flags()` in `bin/shared` (single source):
  `--cap-add DAC_OVERRIDE` added → bounding set is now
  `{NET_ADMIN, SETUID, SETGID, DAC_OVERRIDE}` (CapBnd
  `00000000000010c1`). `no-new-privileges` stays on, read-only rootfs
  stays, nothing else widens
- The `ocs test` harness doors (case-11 peer + the two positive-egress
  listeners) hardcode the *old* cap set inline and crash-loop under a
  non-empty `http-domain-whitelist` for the same reason (the entrypoint
  starts squid in them too) — they now reuse the single-source
  `CAP_FLAGS` (cases 15/16 regressed, case 11 passed for the wrong reason)
- The in-image squid policy files are world-readable now
  (`/etc/squid/squid.conf`, `/etc/squid/squid-whitelist.txt` 0644): they
  are the agent's own egress *policy*, not a credential —
  `/opencode-password` stays `0600`. The suite reads them as `dev`
  (cases 04/20/27 previously failed with "Permission denied").
  `TEST_API` bumped 7→8 so the cached `-test` image is re-baked
- Doc sync: `AGENTS.md` (cap-set bullet + `/opencode-password` note +
  policy-file mode note), `README.md` (cap row), `docker/entrypoint.sh` comment

### Breaking changes

None for users. `docker inspect` of any door now shows
`CapBnd=00000000000010c1` instead of `00000000000010c0`.

### Upgrade steps

- `ocs rebuild` once, then restart whatever door you run. The cap-flag
  change itself is assembled at `docker run` time (no rebuild needed for
  it) — the rebuild re-bakes the world-readable squid policy files and
  picks up v0.7.1's entrypoint fix. `ocs test` rebuilds its `-test`
  image automatically (the TEST_API bump).

### Verification

### Verification

- `shellcheck ocs bin/* bin/shared docker/entrypoint.sh` → clean ✅
- ✅ `ocs rebuild` on Docker Engine 29.9.2 — build-context
  `squid.conf`/`squid-whitelist.txt` now `0644`, image built from the
  precompiled `ocs-base`/`ocs-base-full` (reused)
- ✅ `ocs test` full suite: **28 passed, 0 failed, 1 skipped** — the
  previously failing `15-intranet-endpoint`, `16-host-port` and
  `27-squid-bypass` now pass (listener/peer doors start squid cleanly with
  the new cap set; the in-image squid policy files are readable by `dev`);
  `04-squid-deny` is a legitimate SKIP here — this project's
  `http-domain-whitelist` whitelists `.example.com`, so serving it *is* the
  configured policy (projects without that entry execute the deny path)
- ✅ E2E door `ocs run` → model answered `OCS-OK` (green single run under
  the full flag set incl. `DAC_OVERRIDE`)

### Release metadata (v0.7.2)

- **Base:** `4d04452` (v0.7.1)
- **Commits in range:** `bin/shared` (cap set), `bin/ocs-test`
  (single-source caps in peer/listeners + TEST_API 8),
  `bin/ocs-rebuild-container` (squid policy files 0644),
  `docker/entrypoint.sh` (comment), `AGENTS.md`, `README.md`,
  `RELEASE_NOTES.md`
- **Tag (published):** `RELEASE_V0.7.2-KIDELO` (2026-11-03; v0.7.1 ships
  in this push as commit `4d04452` — both fix the same "squid dies at
  start" report)

---

## v0.7.1 — squid startup fix _(shipped; the full-hardening part it could not see
is fixed in v0.7.2 above)_

**Bug fix: squid was never starting in any project that uses a
non-empty `http-domain-whitelist`.**

`docker/entrypoint.sh` invoked `squid -c "${_SQUID_CONF}"`, but the
config path is a **positional** argument to squid — `squid -c FILE` is
an unrecognized option and aborts with `FATAL: '-c': unrecognized
option or missing required argument` the moment the entrypoint reaches
the proxy block. The bug stayed hidden in this repo's own sandbox
because its `http-domain-whitelist` is empty (squid is skipped there);
any project with whitelisted domains would have died at container
start.

### Highlights

- `squid -c "${_SQUID_CONF}"` → `squid "${_SQUID_CONF}"` (one line in
  `docker/entrypoint.sh` + a comment pinning the positional-argument
  form so it is not "fixed back"), squid still daemonizes and the
  entrypoint's readiness curl still waits for it

### Breaking changes

None — this only repairs a path that could not have worked before.

### Upgrade steps

- `ocs rebuild` (the entrypoint is baked into the image)

### Verification

- **Scope note (superseded by v0.7.2):** the invocations below ran under a
  *lighter* flag set (default caps + `NET_ADMIN`). Under the doors' full
  hardening set (`--cap-drop=ALL` + `no-new-privileges` + read-only/tmpfs)
  squid still failed to start — the cap-set half of the fix shipped in
  v0.7.2 (`DAC_OVERRIDE`).
- ✅ reproduced the bug on the v0.7 image: `squid -c …` → `FATAL:
  '-c': unrecognized option` (container would have failed at start)
- ✅ rebuilt the project image with the fix (bases reused from cache)
- ✅ full entrypoint run with a non-empty whitelist:
  `>> starting squid proxy … >> squid is ready`, no FATAL
  (`--cap-add NET_ADMIN` added in the bare test invocation for the
  firewall step — the real doors pass it via `build_run_flags`)
- ✅ through the live proxy as `dev`: whitelisted `example.com` →
  **200**; IP-literal `1.1.1.1` (rebinding-class attempt) → **403**
- `shellcheck ocs bin/* bin/shared docker/entrypoint.sh` → clean ✅

### Notes (2026-11-03 incident — "docker dies with SETUID enabled")

Audited on Docker Engine 29.9.2 (`containerd-snapshotter` backend) after a
clean `ocs kill`:

- **SETUID exonerated** — the cap set is intact under the new backend
  (`--cap-drop=ALL --cap-add SETUID --cap-add SETGID` → measured CapBnd
  `00000000000000c0`); the daemon never crashed (all dockerd stop/start
  pairs in the journal are host reboots)
- **The `500 invalid tmpfs option "64m"` failures** came from an *old
  ocs client* (pre-v0.4 `bin/shared`) sending the bare
  `--tmpfs /run:64m` short form, which Docker ≥ 29 rejects; the repo's
  `size=64m` key syntax works on both old and new Docker
  (`AGENTS.md`/`README.md` now document this)
- **Reproduced clean**: bare `--tmpfs /run:64m` is rejected by
  Docker 29.9.2, the repo's full flag set is accepted, 3× parallel
  `docker run` (bridge *and* named sandbox network) all come Up, and the
  `ocs kill` → `ocs rebuild` → door E2E path completes green

### Release metadata (v0.7.1)

- **Base:** `ca4abfa` (v0.7 published)
- **Commits in range:** `docker/entrypoint.sh` (squid invocation),
  `RELEASE_NOTES.md`
- **Next tag:** `RELEASE_V0.7.1-KIDELO` (when published)

---

## v0.7 — OpenCode 2.2.5 pin + 2.2.x feature set

The sandbox now ships the newest OpenCode 2 release, **v2.2.5** (2026-10-30).
The pinned CLI moves forward, the standalone-in-docker design and
last-session resume are re-verified against 2.2.5, and the 2.2.x features
that fit a one-shot sandbox are adopted (or deliberately left off).

### Highlights

- **Containers ship OpenCode 2.2.5** — `OPENCODE_BUILD_VERSION` in
  `bin/ocs-rebuild-container` (single source; `--build-arg` to
  `config/base.Dockerfile`, whose `ARG` default + version guard move with it)
  bumped 2.1.2 → 2.2.5; `OCS_BASE_API` bumped 5→6 so cached precompiled
  bases are re-baked once, never stale-reused. Every CLI surface the doors
  rely on was re-verified against the **actual 2.2.5 release binary** before
  shipping: TUI `--standalone --continue/-c --session/-s`,
  `opencode run --standalone -m/--agent/--fork`,
  `opencode serve --hostname --port`, `opencode session list`
- **Standalone mode inside Docker (confirmed on 2.2.5)** — every one-shot
  door keeps using a **private server** (`opencode --standalone` for the
  TUI, `opencode run --standalone` for one-shots), so no shared background
  service can outlive the one-shot container; `ocs start` continues to run
  the foreground `opencode serve`. Bonus from the 2.2.4 line: local
  OpenCode service traffic now explicitly bypasses environment-configured
  proxies, so the in-container squid proxy env stays harmless for the
  client↔server loopback path
- **Last-session resume (verified on 2.2.5)** — session history persists in
  `.sandbox/state/opencode/` (mounted at `/home/dev/.local/share/opencode`);
  `ocs tui -c` (last session) and `ocs tui -s <id>` (specific, id from
  `opencode session list`) both re-checked on the new release
- **`compaction.buffer: "20%"` (2.2.5)** — the shipped
  `config/opencode.jsonc` now sets the new percentage-based compaction
  buffer, keeping 20% of the model's context window free: long agent runs
  survive near-full context without a model-specific token value
- **2.2.x feature awareness (documented, deliberately left off)** — the TUI's
  `/goal <objective>` (the session keeps working until the objective is
  met; `/goal pause|resume|clear`) is documented in README/HOWTO as an
  in-container TUI command; `/schedule` (opt-in `experimental.schedules`) is
  documented as experimental and stays **off** in the shipped config, since
  scheduled wake-ups need a long-running server and one-shot doors never
  outlive their session
- **Docs** — README (current-version note + new "Built-ins available in
  OpenCode 2.2.5" section), HOWTO (5b goal/schedule notes), AGENTS.md
  (current-version pin note), `config/opencode.jsonc` (compaction block)

### Breaking changes

None — the door surface, CLI flags, and config keys are unchanged. The new
`compaction` key is additive (read by 2.2.5+; the pinned CLI is 2.2.5).

### Upgrade steps

- `ocs rebuild` (from the repo) — the precompiled bases re-bake once under
  the new `OCS_BASE_API` 6 label (one-time cost per host), then the
  per-project profile tail layers on top as usual
- `ocs start` / `ocs tui` / `ocs run` / `ocs test` then run OpenCode 2.2.5
  from the rebuilt images
- Existing projects own their `config/opencode.jsonc` — copy the new
  `compaction` block from the repo template to pick up the 20% buffer
  (optional; the key is a 2.2.5+ feature and not required)

### Verification

Partially verified on the release host (Docker 29.9.2, profile `full`,
first-run host — bases re-baked from scratch); the remaining smoke steps
(one-shot `ocs run`, full `ocs test` suite) were dropped on request.

- ✅ `ocs rebuild` — both precompiled bases re-baked under `ocs-base-api=6`,
  `full` profile image built, exit 0
- ✅ image check — `opencode --version` inside the built image: **v2.2.5**
  (the `config/base.Dockerfile` version guard also enforces this at build)
- ✅ `ocs start` — `opencode serve` 2.2.5 up on `127.0.0.1:4096`;
  **401** unauthenticated → **200** with basic auth
  (`opencode:<.sandbox/build/opencode-password>`); API self-reports
  `{"version":"2.2.5"}`
- ✅ every flag the doors rely on was re-verified against the **2.2.5 release
  binary** before shipping: TUI `--standalone -c/-s`, `run --standalone
  -m/--agent`, `serve --hostname --port`
- ⬜ `ocs tui` resume (`-c` / `-s <id>`) — not run in this cycle
- ⬜ `ocs run` one-shot, `ocs test` full suite — not run in this cycle
- `shellcheck ocs bin/* bin/shared docker/entrypoint.sh` → clean ✅

### Release metadata (v0.7)

- **Tag (published):** `RELEASE_V0.7-KIDELO`
- **Base:** `3de35c3` (v0.6 TUI keybind doc fix)
- **Commits in range:** `bin/ocs-rebuild-container` (version + `OCS_BASE_API`),
  `config/base.Dockerfile` (`ARG` default), `config/opencode.jsonc`
  (compaction buffer), `README.md`, `HOWTO.md`, `AGENTS.md`,
  `RELEASE_NOTES.md`

---

## v0.6 — plan mode, custom agents & skills, todo verified

OpenCode 2's built-in **Plan** agent (a read-only primary agent) is now
first-class in every door, the **todo** tool — which V2 drops from the
default toolset — is verified *on* and working, and **custom agents and
skills** (an OpenCode 2 flagship) ship as bundled defaults with first-run
seeding into each project's workspace.

### Highlights

- **`ocs plan` door** — plan-mode one-shot: identical to `ocs run`, pinned to
  OpenCode's built-in **Plan** primary agent (`--agent plan` is forwarded to
  `opencode run`). The Plan agent explores the codebase and discusses a plan
  with you **without editing normal project files** (edits are denied; only
  `~/.opencode/plan/*` is writable)
- **Plan mode in the TUI** — **Shift+Tab** (OpenCode 2's built-in agent
  switch; Tab keeps its input-autocomplete job) cycles the primary agents
  live (Build → Plan → Build, verified in the real TUI); switching
  Plan→Build injects a `build-switch` system reminder. Plan first,
  review, Shift+Tab back to Build, implement
- **`ocs run --agent <id>`** — extra args already pass through to
  `opencode run`; the Plan agent is now a documented first-class example
  (`ocs run <name> "plan this" --agent plan`)
- **todo tool verified (2.1.2)** — OpenCode 2 ships the V1-era `todowrite`
  tool **off by default**; the enabling key is `experimental.todo: true`
  (already in the shipped `config/opencode.jsonc`; comment updated to
  "verified"). Proven live: the model called `todowrite` (a two-item list)
  with `status=completed`; the TUI renders the task list
- **Custom agents + skills (new)** — OpenCode 2's agent/skill system is
  adopted project-scoped: agents/skills live in `<workspace>/.opencode/`
  (the persistent rw dir; container CWD is `/workspace`, so OpenCode
  discovers them without any image change). Two bundled defaults are seeded
  on the **first door run** of every project (host-side, idempotent,
  first-run-only — after that the files are yours; delete the dir to get
  the defaults back):
  - **`reviewer`** — a `subagent`, read-only by construction (`edit` +
    `shell` both denied in its frontmatter), used for code review
  - **`todo-workflow`** — a skill teaching the multi-step discipline:
    `todowrite` list (pending → in_progress → completed) for longer tasks
  - Single source: `config/default-agents/` + `config/default-skills/`;
    seeding via `seed_workspace_opencode()` in `bin/shared`, called from
    `build_run_flags` (every door), so no rebuild is ever needed for it
- **Docs** — README (new `ocs plan` section + door list + "Custom agents &
  skills" section), HOWTO (5b Shift+Tab switching, 5c `--agent plan` + 5c+
  `ocs plan`, **new §8 "Custom agents and skills"** with the location
  table, defaults, and your-own examples; Hooks/Daily/Troubleshooting
  renumbered 9/10/11), AGENTS.md (door surface + seeding contract),
  `ocs` help / `ocs-run` usage

### Breaking changes

None — purely additive (one new door; no flag/config changes).

### Upgrade steps

None — `ocs plan` and the agent/skill seeding are both host-side (no
rebuild required). The first door run of an existing project seeds
`<workspace>/.opencode/{agents,skills}` once (reviewer subagent +
todo-workflow skill) — skip the check if you already have that dir.
Projects whose `config/opencode.jsonc` predates v0.5 should take the repo
template (v0.5 upgrade steps) to pick up the `experimental.todo` enablement.

### Verification

- **E2E through the sandbox:** `ocs plan 20o "Reply with exactly:
  OCS-PLAN-OK"` — full path (dispatcher → ocs-run → entrypoint eval →
  `opencode run --standalone -m ollama/qwen3.8:27b --agent plan`): agent
  banner `> plan · qwen3.8:27b`, reply `OCS-PLAN-OK`, rc=0, all hardening
  layers applied (agent-DNS gate, QUIC/DoT drops, git-hook sink, ro-rootfs,
  limits)
- **CLI-level:** `opencode run --standalone -m <model> --agent plan "…"` — the
  exact command form the door produces, verified cold
- **TUI live switch (via `ocs tui`):** a PTY-driven session through the full
  door stack, header read after each keystroke — start: `Build ·
  Qwen3.8 27B Ollama`, after one **Shift+Tab**: `Plan · Qwen3.8 27B
  Ollama`, after a second: back to `Build …`. Confirms the stock
  2.1.2 default keybind (`agent.cycle` = `shift+tab`,
  `agent.cycle.reverse` unbound) in the real TUI
- **todo live probe (2.1.2 server API):** assistant `todowrite` tool call
  `status=completed` (two-item todo list); V2's plan switch confirmed via
  `session.switchAgent` (HTTP 204) + the synthetic "You are in Plan mode"
  system message
- **Agents/skills E2E through the sandbox:** first door run seeded
  `sandboxes/20o/workspace/.opencode/{agents,skills}/{reviewer.md,
  todo-workflow.md}`; `ocs run 20o "…load the skill with id 'todo-
  workflow'… reply SKILL-OK"` → skill loaded (transcript shows
  `→ Skill "Multi-step todo workflow"`) → `SKILL-OK`, rc=0;
  `ocs run 20o "…ask the 'reviewer' subagent … reply REVIEWER-OK"` →
  delegation to the reviewer subagent (transcript shows the reviewer
  subagent call) → `REVIEWER-OK`, rc=0
- `shellcheck` clean across `ocs bin/* bin/shared docker/entrypoint.sh`

### Release metadata (v0.6)

- **Tag (planned):** `RELEASE_V0.6-KIDELO`
- **Base:** `aa9800e` (v0.5 docs)
- **Commits in range:** `ocs` (new `plan` case arm + usage + header),
  `bin/ocs-run` (usage example), `bin/shared` (`seed_workspace_opencode()`
  + call in `build_run_flags`), `config/default-agents/reviewer.md` +
  `config/default-skills/todo-workflow.md` (bundled defaults, single
  source), `README.md`, `HOWTO.md`, `AGENTS.md`, `config/opencode.jsonc`
  (todo comment, verified)

---

## v0.5 — OpenCode 1.x → 2.1.x migration *(published 2026-10-22)*

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

- **Tag:** `RELEASE_V0.5-KIDELO` (published 2026-10-22)
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
| **v0.8.1** | **detached TUI truecolour** — pane starts with TERM=xterm-256color + COLORTERM=truecolor (the TUI's renderer fell back to 16-colour under tmux's default TERM=screen) | `RELEASE_V0.8.1-KIDELO` (published) |
| **v0.8** | **detached TUI** — `ocs tui --detach/--attach/--stop/--status`: TUI in tmux in a long-lived container, leave with Ctrl-B D, the agent keeps working; `tmux` in `ocs-base` | `RELEASE_V0.8-KIDELO` (published) |
| **v0.7.2** | **squid under full hardening** — worker died under `cap-drop=ALL` + `no-new-privileges`; `CAP_DAC_OVERRIDE` added (bisected; CHOWN/FOWNER not sufficient) | `RELEASE_V0.7.2-KIDELO` (published) |
| v0.7.1 | squid startup fix — `squid -c FILE` FATAL on any whitelisted-domain project; config path is positional now | shipped in the v0.7.2 push (commit `4d04452`) |
| v0.7 | **OpenCode 2.2.5 pin** (latest) + standalone-in-docker & last-session resume re-verified + `compaction.buffer: 20%` shipped + `/goal` & `/schedule` awareness | `RELEASE_V0.7-KIDELO` (published) |
| v0.6 | Plan-mode door (`ocs plan`) + TUI Shift+Tab agent switching (verified live) + custom agents/skills (defaults + first-run seed) + `todo` tool verified on 2.1.2 | `RELEASE_V0.6-KIDELO` (planned) |
| v0.5 | **OpenCode 1.x → 2.1.x migration** (doors, entrypoint auth, config shape, base, `TEST_API` 7) | `RELEASE_V0.5-KIDELO` (published) |
| v0.4 | Extra hardening (seccomp / landlock / egress-audit / sensitive-paths / git-hook sink / squid rebinding) + test cases 24–29 | — (local) |
| v0.3 | Per-project policy knobs + read-only rootfs / sized tmpfs / IPv6-off | — (local) |
| v0.2 | TUI resume, `status`/`logs`, CLI pin, precompiled bases, resource limits, agent-DNS gate, 21-case suite | `RELEASE_V0.2-KIDELO` (local) |
| v0.1 | First public release | `RELEASE_V0.1-KIDELO` (published) |
