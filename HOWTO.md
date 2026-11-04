# How to — set up a sandbox and run OpenCode in it

This guide walks through the full lifecycle: installing the tool, initialising one project, and the different ways to run OpenCode inside its sandbox container. For the reasoning, design decisions and developer conventions see [AGENTS.md](AGENTS.md); for the option-by-option reference see [README.md](README.md).

> **Who this is for:** a developer who wants to run OpenCode (the AI coding assistant) for *a specific project* inside an isolated Docker container, scoped to that project's files and a controlled network.

---

## 1. Prerequisites

- A Docker-compatible runtime (Docker, Podman, or Colima). This project was tested on Linux with Docker.
- A network that can reach `opencode.ai` at **image-build time** (the OpenCode installer) — this is a host-side build dependency, not a runtime sandbox rule.
- A runtime network that can reach your **model endpoint** (e.g. an Ollama server) — this **is** listed in the sandbox config under `intranet-endpoints`, see `config/opencode-sandbox-config.yaml`.
- Optionally the [opencode](https://opencode.ai/) CLI on your host, for the TUI / one-shot modes (`ocs tui`, `ocs run`). Not required for the web UI.

> **You do not need** Node, mise, or any toolchain on the host. The container installs everything it needs via `apt` at image-build time.

---

## 2. Install

Clone this repository and add the **repository root** to your `PATH`:

```bash
git clone https://github.com/kidelo/opencode-sandbox.git
export PATH="/path/to/opencode-sandbox:$PATH"
```

Put the `export` line in your shell profile (`.zshrc` / `.bashrc`) to make it permanent. The single `ocs` command is now available globally — all sandboxes are addressed through it.

---

## 3. Initialise a project (`ocs init`)

New sandbox projects always land under `./sandboxes/` inside this repository (override with `$OPENCODE_SANDBOX_BASE`), so every sandbox lives in one place:

```bash
ocs init my-sandbox        # → ./sandboxes/my-sandbox/
```

`my-sandbox` is the sandbox name (lowercase letters, digits, hyphens). It interactively asks for each step (default: yes):

1. **`config/opencode-sandbox-config.yaml`** — copied from this repo's own `config/` (the single source of truth). Pre-filled with `sandbox-name` set to the project name and `opencode-port`.
2. **Container image profile** — the list of `config/Dockerfile.*` files (minus the reserved `test` one) is shown and your choice is written as the `dockerfile:` key in the config (default: `minimal` — harness + `python3`; pick `full` for the complete dev toolchain).
3. **`config/opencode.jsonc`** — OpenCode model / provider / permission policy (same content for every project; change it if you use a different model).
4. **`opencode-sandbox-pre-start-container.sh`** — an empty hook (see [Hooks](#8-hooks)) that you can use to export short-lived credentials at start time.
5. **Build the image** by running `ocs rebuild` (see below).

After this, the project directory contains:

```
sandboxes/my-sandbox/
├── config/
│   ├── opencode-sandbox-config.yaml   # the only file you normally edit (incl. dockerfile: minimal|full)
│   └── opencode.jsonc                 # model / provider / permissions
└── opencode-sandbox-pre-start-container.sh
```

> **New projects are gitignored** by default — they stay local to your checkout. A new project ships with: a single read-write `workspace/` dir (its source + data, mounted at `/workspace`), a model endpoint (`intranet-endpoints`), and a model/provider/permission config. You add a one-shot `prompt.md` under `workspace/` whenever you want to drive a specific task with `ocs run my-sandbox workspace/prompt.md`.

---

## 4. Build the image (`ocs rebuild <name>`)

Run from any directory — you address the project by name (the `bin/` scripts find it via the `config/` marker):

```bash
ocs rebuild my-sandbox
```

What it does:

1. Reads `sandbox-name` from `config/opencode-sandbox-config.yaml` and combines it with a short hash of the project root path to form a `SANDBOX_ID` (e.g. `my-project-a3f92c`).
2. Creates the per-project tree `<project>/.sandbox/{build,state}/`; generates a random web-server password in `build/opencode-password` **only if one does not exist yet** (a rebuild reuses the existing password — it never rotates, so already-authenticated clients keep working; delete the file to force a new one).
3. Extracts the config into build artifacts: domain whitelist, host ports, intranet endpoints, env passthrough, volume mounts — and the sandbox network CIDR range.
4. Ensures the two **precompiled base images** exist on this host (building them once if they're missing or stale): `ocs-base` (the common packages + `dev` user + OpenCode download, from `config/base.Dockerfile`) and — for the `full` profile — `ocs-base-full` (which adds the dev toolchain, from `config/base-full.Dockerfile`).
5. Builds the Docker image `ocs-<SANDBOX_ID>` by layering the thin per-project tail (squid/firewall config, password, `entrypoint.sh`) on top of the right base, from the profile named by the `dockerfile:` key (`config/Dockerfile.minimal` / `Dockerfile.full`).

Because the expensive shared layers live in those once-per-host base images, step 5 is a matter of **seconds** regardless of profile — the first `ocs rebuild` on a host pays for the base(s), everything after is fast.

> **Run this again whenever** `config/opencode-sandbox-config.yaml`, `config/opencode.jsonc`, `config/Dockerfile.<profile>`, `config/base.Dockerfile`, `config/base-full.Dockerfile` or `docker/entrypoint.sh` change. The image is the **only** persistent artifact — there is no long-running sandbox container to keep updated.

---

## 5. Running OpenCode — your options

There are four ways to run, all of which use the same image and the same sandbox (firewall + network isolation). You address the project **by name**, e.g. `my-sandbox`:

| Goal | Command | Container lifetime |
|---|---|---|
| **Web UI** (browser) | `ocs start my-sandbox` then `ocs web my-sandbox` | lives while the terminal is open |
| **TUI** in your terminal | `ocs tui my-sandbox` | one-shot, dies when you `/exit`; `-c`/`-s <id>` resume an aborted session |
| **One-shot** from a prompt file | `ocs run my-sandbox prompt.md` | one-shot, dies when the task ends |
| **Programmatic check / CI** | `ocs test my-sandbox` | one-shot (its own test container), always removed |

All four share the same sandbox guarantees: unprivileged `dev` user, Squid domain whitelist, iptables default-deny egress, dedicated Docker network, **no** Docker daemon access.

---

### 5a. Web UI — `ocs start <name>` + `ocs web <name>`

```bash
ocs start my-sandbox      # starts a web container (Ctrl+C stops + removes it)
ocs web my-sandbox        # opens http://127.0.0.1:<port> in your browser
```

Authenticate in the browser with:

- **Username:** `opencode`
- **Password:** the contents of `<project>/.sandbox/build/opencode-password`
  (or use `ocs web-auth my-sandbox` to open a pre-authenticated URL for the first visit)

`ocs terminal my-sandbox` attaches an OpenCode terminal session to this running web container.

> **Parallel projects:** each sandbox exposes its web port on `127.0.0.1`. If two sandboxes on the same host use the same `opencode-port`, the second start fails with "port already allocated". Give parallel projects different `opencode-port` values, or use the one-shot modes (`ocs run <name> …`, `ocs tui <name>`) which publish no port at all.

---

### 5b. Interactive TUI — `ocs tui [name] [resume-flags]`

Drops straight into the **opencode terminal (TUI)** as the `dev` user in a one-shot container. Squid + firewall are applied first (by the entrypoint), so the session is sandboxed exactly like the web one.

```bash
ocs tui my-sandbox
```

Leave with `Ctrl+D` or `/exit`; the container is removed automatically. No web server is started.

**Resuming an aborted session.** Session history survives between runs, so if a TUI run aborts (lost connection, `Ctrl+C`, …) you can continue where it left off:

```bash
ocs tui my-sandbox -c            # continue the last session
ocs tui my-sandbox -s ses_…      # continue a specific session by id
```

You can also omit the name when you are inside the project: `ocs tui -c` (the project is resolved from the current directory). `-c` and `-s` are mutually exclusive; unknown flags fail loudly. (OpenCode 2 dropped the V1 `--fork` TUI flag — fork from within the TUI, or via `opencode run --fork` for automation.)

**Plan mode (build it after you've planned it).** OpenCode ships a read-only **Plan** primary agent alongside **Build**. Press **Shift+Tab** in the TUI to cycle the primary agents (the built-in OpenCode 2 default — Tab stays with its input-field autocomplete job) — in Plan mode the agent explores the codebase and discusses the plan with you without editing your project files; when the plan looks right, Shift+Tab back to Build and ask it to implement. (The same switch exists for one-shot runs — see 5c / `ocs plan`.) Prefer **Tab** yourself? Remap it in your TUI settings: `{"keybinds": {"agent_cycle": "tab,shift+tab"}}` in `~/.config/opencode/tui.json`.

**Keep working toward a goal (new in OpenCode 2.2.5).** Type `/goal <objective>` in the TUI: the session keeps going while an automatic review checks progress, until the objective is met — `/goal pause`, `/goal resume`, and `/goal clear` control it. It is a TUI session command; the one-shot doors (`ocs run` / `ocs plan`) don't run it. OpenCode 2.2.x also ships scheduled prompts (`/schedule`, opt-in `experimental.schedules`) — left **off** in the shipped config, since the one-shot doors never outlive their session and a scheduled wake-up only makes sense in a long-running `ocs start` server.

---

### 5c. One-shot with a prompt — `ocs run [name] <prompt>`

Runs a single `opencode run` (model pinned) with a prompt — either the **contents of a markdown file** or an **inline prompt string**. Ideal for scripted / CI-style tasks:

```sh
ocs run my-sandbox prompt.md                 # name + prompt file
ocs run my-sandbox "summarise this repo"     # name + inline prompt string
ocs run prompt.md                            # from inside a project (project resolved from cwd)
ocs run "summarise this repo"                # inline; project resolved from cwd
ocs run my-sandbox prompt.md -f context.md   # extra args pass through to `opencode run`
```

- A prompt file **inside** the workspace is read in place; a file **outside** is mounted into the container read-only for that run. An **inline** prompt is written to a temp file, mounted read-only for the run, and removed afterward.
- The model is **always pinned** to the configured sandbox model — it cannot be switched in-session.
- `webfetch` / `websearch` are denied by the OpenCode config; any web egress must also pass the Squid / iptables firewall.
- **Plan mode:** `ocs run my-sandbox "plan this" --agent plan` (or use the dedicated door below) runs the session with OpenCode's read-only **Plan** agent — explore + plan, no edits to your project files.

#### 5c+. Plan-mode one-shot — `ocs plan [name] <prompt>`

Identical to 5c, pinned to the Plan agent (the 5b Shift+Tab-switch, for the one-shot door):

```sh
ocs plan my-sandbox "design a migration to SQLite"   # name + prompt
ocs plan "draft an implementation plan"              # from inside a project
```

---

### 5d. Security test — `ocs test <name>`

Runs the sandbox security suite in its own one-shot container (no web container needed), which is always removed afterwards. It builds from the reserved `config/Dockerfile.test` profile (a network-analysis image: `nmap`, `tcpdump`, DNS tools, `python3`, `jq`) under its own tag `ocs-<SANDBOX_ID>-test`, so it does **not** touch the project's working image (built from `minimal` or `full`). The test image is **kept on a pass** (cached for a fast re-run) and **removed on a fail/crash** (plus by `ocs clean` / `ocs kill`):

```bash
ocs test my-sandbox
```

It checks (deterministic + an AI-agent red-team) that egress is blocked, no sensitive files are readable, no Docker escape channel exists, and the sandbox is on its own isolated network on the configured IP range.

> **If a case fails** (or the run is interrupted), `ocs test` **removes the test image** (`ocs-<SANDBOX_ID>-test`) so only known-good builds remain. Your working image is untouched.

### 5e. Seeing what's running — `ocs status` and `ocs logs`

Two inspection helpers that do **not** start a container:

```sh
ocs status                # which sandbox containers exist right now (running + stopped)
ocs status my-sandbox     # only containers matching "my-sandbox" (substring)
ocs logs                  # last 200 lines of this project's container log
ocs logs -f               # follow the log live (Ctrl+C to stop)
ocs logs -n 50            # only the last 50 lines
```

`ocs status` is the "what containers are there?" view (a filtered `docker ps`); `ocs logs` reads the log of the existing container for a project, passing flags straight through to `docker logs`. The name is optional when you run it from inside a project (resolved from the current directory).

> **One-shot caveat:** most doors (`ocs tui` / `ocs run` / `ocs test`) use `--rm`, so their containers disappear on exit and their logs are only available while the door is still alive. `ocs logs` will tell you if the container is gone and point you at `ocs status`.

---

## 6. Working directories (where OpenCode "lives")

This is the most common source of confusion. There are **three** distinct locations that are easy to mix up:

| What | Inside the container | On your host | Role |
|---|---|---|---|
| **Workspace** | `/workspace` (fixed path, from the `workspace:` config key; the repo self-host uses `.`) | the project's workspace dir (default `workspace/`) | The project. OpenCode opens and edits here (container `WORKDIR` is `/workspace`). |
| **Dev user home** | `/home/dev` — holds OpenCode's state `.local/share/opencode` | `<project>/.sandbox/state/opencode` | OpenCode session history, config cache. Not your project code. |
| **Sandbox build/state** | — (host only) | `<project>/.sandbox/{build,state}/` | Password, port, extracted config artifacts (build/); session + subnet map (state/). Never committed. |

**Key points:**

- The "workspace home dir" is the **fixed in-container path `/workspace`** (from the `workspace:` key, default `workspace/`; the repo self-host uses `.`). It is baked in as `WORKDIR /workspace` in every profile, so the entrypoint `cd`s there and OpenCode sees project files at one stable path regardless of where the project lives on the host.
- The workspace mount is a **single read-write dir** at that fixed `/workspace` path (not a 1:1 host-path mapping) — no host path to remember, and no part of the host tree outside the workspace (or the `.sandbox` runtime tree) is ever visible.
- The `dev` user home (`/home/dev`) is a *separate*, unprivileged location for OpenCode's state. It is intentionally **not** your workspace, so session data stays in its own tree (`.sandbox/state/opencode`) and your project source stays clean.
- `<project>/.sandbox/` holds **all** sandbox build + state on the host. It is git-ignored by the `.sandbox` entry in `.gitignore` and is never mounted in as a source (only `state/opencode` is mounted, into `/home/dev/.local/share/opencode`).
- `ocs kill` (containers, images, networks) leaves `.sandbox/` in place. `ocs kill --purge my-sandbox` also removes `.sandbox/build/` (disposable — safe to lose); `ocs kill --state my-sandbox` also removes `.sandbox/state/` (your session).

---

## 7. Configuring the sandbox

The file you almost always edit is `config/opencode-sandbox-config.yaml`:

```yaml
sandbox-name: my-project        # label used in SANDBOX_ID
opencode-port: 4096             # host port for the web UI
sandbox-network-cidr: 10.77.0.0/16   # dedicated network range (containers live on 10.77.x.x)
dockerfile: minimal             # image profile -> config/Dockerfile.minimal (minimal | full)
workspace: workspace            # the single rw dir (default); mounted at /workspace

http-domain-whitelist:          # outbound HTTP/HTTPS allowed via the proxy — empty = deny all
  # - .github.com               #   leading dot = domain + subdomains
  # - registry.npmjs.org

host-ports:                     # disabled by default — no host TCP ports reachable unless added
  # - 5432                      #   reach via the hostname `docker.host`

intranet-endpoints:             # ip:port services reachable directly (no proxy)
  - 192.168.0.10:11434          #   e.g. your on-prem Ollama / database (use your own)

agent-dns: deny                 # deny (default) = no DNS exfil channel; allow = agent may resolve hostnames

env-passthrough:                # host env → container (values read at start time)
  GH_TOKEN: GH_TOKEN

volume-mounts:                  # extra host dirs mounted read-WRITE
  # /cache: "$HOME/.cache/my-project"

read-only-mounts:               # extra host dirs mounted READ-ONLY (agent can read, not write)
  # /data: "$HOME/datasets"

# Per-project policy (optional; defaults shown). See README → Per-project policy.
# cpus: 2.0
# memory: 4g
# pids: 256
# disk: 8g                      # max size of a single file (RLIMIT_FSIZE)
# nofile: 8192                  # max open file descriptors (RLIMIT_NOFILE)
# timeout: 0                    # wall-clock cap for `ocs tui` / `ocs run` (0 = none)
# model: ollama/qwen3.8:27b     # -m pin for `ocs run`; display only for `ocs tui` (the V2 TUI has no --model flag — its model is the config `model` pin)

# Extra hardening (optional; defaults shown). See README → Extra hardening.
# seccomp: on                   # on | off — Docker default seccomp profile (off = opt-out)
# landlock: off                 # on | off — kernel-enforced write boundary (opt-in, kernel >= 5.13)
# egress-audit: off             # on | off — squid access-log to /run/squid-access.log
sensitive-paths:                # extra workspace sub-paths to pin READ-ONLY (adds to the built-in set)
  # - .github/
```

- **`http-domain-whitelist`** — domains the Squid proxy will forward. **Empty by default — nothing is allowed until you add a domain.** A leading dot covers subdomains.
- **`host-ports`** — for databases/servers on the host machine. **Disabled by default (empty)**; add ports only if needed. Use the hostname `docker.host` (not `localhost`) inside the container.
- **`intranet-endpoints`** — for on-prem services on other machines. This must include your model endpoint or the agent cannot reach it (see `ocs test` SKIP hint). Endpoints are `ip:port` **by design** — the agent's own DNS is denied by default (`agent-dns: deny`), so nothing inside the container may rely on hostname resolution for endpoints.
- **`agent-dns`** — `deny` (default) or `allow`. `deny` is the secure path (no DNS exfil/C2 channel); `allow` re-opens the resolver for the agent — only turn this on when an endpoint must be a hostname (e.g. model `baseURL`).
- **`env-passthrough` / `env`** — credentials (via passthrough; passed at start time through a per-run `0600` env file, so they never appear on the `docker run` command line) and non-secret context (via `env`).
- **`volume-mounts` / `read-only-mounts`** — extra host directories mounted into the container (`CONTAINER_DIR: HOST_DIR`), read-write or read-only respectively. The workspace stays the only writable output dir; use `read-only-mounts` for input/reference data.
- **`sandbox-network-cidr`** — the private range all your sandboxes draw from; each sandbox gets its own `/24` inside it, L2-separated from the others.

`config/opencode.jsonc` sets the model, provider (`baseURL` of your Ollama server) and OpenCode permissions (`webfetch` / `websearch` denied by default). Change it if you point at a different model.

**How the model pin works (and how to verify it).** The file is mounted **read-only** at `/etc/opencode/opencode.jsonc` and `OPENCODE_CONFIG` is pointed at it — OpenCode reads it on every start (CLI and server alike). Three keys do the pinning, verified working on OpenCode 2.2.5:

- `model` — the default model, e.g. `"ollama/qwen3.8:27b"`;
- `enabled_providers` — the **catalog lever**: with `["ollama"]` OpenCode normalises a policy that *denies every other provider*, so the built-in free catalog (`opencode/…`) never appears in the model list or the TUI picker;
- the model's `limit.context` / `limit.output` — the values the TUI context meter and compaction read.

The V1-shaped (`provider`/`npm`/`options`/`permission`) and the V2-shaped (`providers`/`package`/`settings`/`permissions`) config both parse and pin correctly on 2.2.5 — the live schema (`https://opencode.ai/config.json`) accepts both; the installed binary is the source of truth.

Quick checks (with a door running, or a one-shot container):

```bash
# 1) inside the container, as the dev user:
opencode models                # must list exactly the pinned model — nothing else

# 2) from the host, against a running web door (basic auth):
PW=$(cat .sandbox/build/opencode-password)
curl -s -u "opencode:$PW" http://127.0.0.1:<port>/api/model | python3 -m json.tool
# → exactly one entry, with "limit": {"context": …, "output": …}
```

`ocs test` case 30 re-runs check 1 inside a fresh container on every test run, so a regression to "all models / broken limit" fails the suite instead of silently happening.

> **Any change to `config/…` requires a rebuild:** `ocs rebuild`. (The `opencode.jsonc` itself is a **live** ro mount — no rebuild needed, only a re-run of the door.)

---

## 8. Custom agents and skills (OpenCode 2)

OpenCode 2 supports **custom agents** (named, purpose-specific assistants) and **skills** (reusable how-to documents the model loads on demand). In the sandbox they live **project-scoped** in your workspace:

| What | Location (host) | Location (container) |
|---|---|---|
| Agents | `<workspace>/.opencode/agents/<name>.md` | `/workspace/.opencode/agents/` |
| Skills | `<workspace>/.opencode/skills/<id>.md` (flat) or `<id>/SKILL.md` | `/workspace/.opencode/skills/` |

The workspace is the persistent rw dir, so anything you add here survives across runs. OpenCode discovers them automatically — the model sees the agent catalog (subagents) and the skill descriptions, and loads a skill with the `skill` tool or by writing `@skill-id` in your prompt.

### 8.1 What ships by default

On the first run of a door (start / tui / run / test) the sandbox seeds a small default set into `<workspace>/.opencode/` — one time, host-side, no rebuild needed:

- **`reviewer`** (subagent, read-only by construction — `edit` and `shell` are denied): code review. Use it via `subagent_type: "reviewer"`, or just ask the main agent to "review the changes".
- **`todo-workflow`** (skill): a todo-list discipline for multi-step work — create a list with the `todowrite` tool, work through it, and keep it updated. Load it with `@todo-workflow` or the `skill` tool, id `todo-workflow`.

Once seeded, the dir is **yours**: edit or delete the files freely. Want the defaults back? Delete `<workspace>/.opencode/agents` (or `…/skills`) and the next door run re-seeds it.

### 8.2 Adding your own

**Agent** — `<workspace>/.opencode/agents/summarizer.md`:

```markdown
---
description: Summarises any file or change into a tight digest
mode: subagent
---

You are a summariser. Return 5 bullets: what it does, what changed, why,
risky bits, follow-ups. Be specific (files, lines, identifiers).
```

**Skill** — `<workspace>/.opencode/skills/release-notes.md` (flat form, single file):

```markdown
---
name: Release notes
description: How to write the project's CHANGELOG entries - load it when asked to prepare a release
---

Write release notes as: ## vX.Y.Z, then ### Added / ### Changed / ### Fixed
with one line per item and a concrete reference (flag, file, issue).
```

Notes:

- **IDs** are the filename (flat) or directory name (folder form), kebab-case — that's what the model loads with the `skill` tool (`{"id": "release-notes"}`).
- **`description` in the frontmatter is what the model sees** — write it for the model, not for humans ("Use for …" beats "A tool for …").
- **`mode: subagent`** agents can be delegated to via the `subagent` tool; `mode: primary` agents can be picked directly in the TUI (Shift+Tab-cycle, the built-in agent switch) and via `ocs run <name> "…" --agent <id>`.
- **Permissions**: per-agent `permissions:` in the frontmatter (see the built `plan` agent — read-only by default) or globally in `opencode.jsonc`. The action list includes `skill` (lock a skill to an agent) and `external_directory` (stop reads outside the workspace).
- **`default_agent`** in `opencode.jsonc` (`"default_agent": "plan"`) changes which primary agent starts a `ocs run` session.
- **Built-in agents** you can already use: `build` (default, full tools), `plan` (read-only planning — see the Plan-mode note in Section 5b above), plus subagents `general` and `explore`.
- No sandbox rebuild is needed for any of this — agents/skills are live files in the workspace; the sandbox just seeds the defaults and mounts the dir.

---

## 9. Hooks

If `opencode-sandbox-pre-start-container.sh` exists in the project root, `ocs start` **sources** it (not executes) before starting the container. Use it to refresh short-lived credentials:

```bash
#!/usr/bin/env bash
aws sso login --profile my-profile
eval "$(aws configure export-credentials --profile my-profile --format env)"
# export AWS_ACCESS_KEY_ID / _SECRET_ACCESS_KEY / _SESSION_TOKEN so env-passthrough picks them up
```

If it contains secrets, add it to `.gitignore`.

---

## 10. Daily / maintenance commands

| Situation | Command |
|---|---|
| First-time setup | `ocs init my-sandbox` then `ocs start my-sandbox` |
| Daily use (web) | `ocs start my-sandbox` then `ocs web my-sandbox` |
| Daily use (TUI) | `ocs tui my-sandbox` |
| Resume an aborted TUI session | `ocs tui my-sandbox -c` (last) · `-s <id>` (one) |
| One-shot task | `ocs run my-sandbox prompt.md` |
| After a config/Dockerfile change | `ocs rebuild my-sandbox` then your run command |
| Verify sandbox security | `ocs test my-sandbox` |
| List sandbox projects | `ocs list` |
| See running sandbox containers | `ocs status` (or `ocs status my-sandbox`) |
| Read / follow a container's log | `ocs logs my-sandbox` (or `ocs logs -f`) |
| Wipe one sandbox completely (image + network + state) | `ocs clean my-sandbox` |
| Full cleanup of all sandboxes on this host | `ocs kill` |
| Stop the web container | `Ctrl+C` in the `ocs start my-sandbox` terminal |
| Clean up after a crash / hard abort (all sandboxes) | `ocs kill` |

---

## 11. Troubleshooting

- **"port is already allocated"** — two sandboxes are using the same `opencode-port`. Use different ports, or switch to the portless one-shot modes.
- **"I see all the models / the context limit looks wrong"** — the model pin lives in `config/opencode.jsonc` (see §7: `model` + `enabled_providers` + `limit.context`). Check, in order: (1) the file exists in **this project's** `config/` dir (every sandbox mounts its *own* copy — an old project may still hold a pre-v0.7 stale one); (2) a door/container started **before** the config was fixed still runs the old state — stop and re-run it (`ocs kill <name>` + start); (3) verify with `opencode models` inside a fresh container — it must list exactly one model. `ocs test` case 30 covers this regression.
- **Agent case SKIPs in `ocs test`** — the model endpoint (your Ollama `ip:port`) is not reachable from the container. Add it to `intranet-endpoints` in `config/opencode-sandbox-config.yaml` and rebuild.
- **The agent cannot resolve a hostname (DNS "no answer"/timeout)** — expected with the default `agent-dns: deny` (the DNS exfil/C2 channel is closed). Two options: address the endpoint by IP (`intranet-endpoints: - ip:port`, and give the model `baseURL` an IP), or set `agent-dns: allow` in the config and rebuild if you accept the DNS exfil risk.
- **A test case FAILed and the image vanished** — by design. `ocs rebuild` brings it back.
- **Container runs out of memory / is killed (OOM) or feels CPU-limited** — every sandbox runs with host-DoS guards by default: `--memory=4g --memory-swap=4g --cpus=2.0 --pids-limit=256 --ulimit=fsize=8g --security-opt=no-new-privileges:true`, plus a **read-only rootfs with sized tmpfs** for `/tmp` / `/run` / `/var/tmp` / `$HOME` and **IPv6 disabled** in the namespace (see README → Network isolation). Override per project with the `cpus:` / `memory:` / `pids:` / `disk:` policy keys in `config/opencode-sandbox-config.yaml`, run `ocs rebuild`, and start again — no image rebuild needed.
- **A write fails with "File too large" / the agent cannot create a big file** — the `disk:` policy key (default `8g`) caps the size of a single file (`RLIMIT_FSIZE`). Raise it in `config/opencode-sandbox-config.yaml` and `ocs rebuild` if the project legitimately needs larger files. Note this caps one file, not total disk usage.
- **A write fails with "Read-only file system" (EROFS)** — by design. The container root filesystem is read-only: only `/workspace`, the opencode state dir (`~/.local/share/opencode`), and any `volume-mounts` you configured are writable. `/tmp`, `/run`, `/var/tmp`, `~/.cache`, `~/.config` and `~/.local/state` are sized **tmpfs** (ephemeral, bounded by the memory limit). Write outputs under `/workspace` (or add a `volume-mounts` entry) instead of system paths.
- **`ocs test` case 11 says "peer container not started"** — the runner could not bring up the second isolation-check container (e.g. image missing or runtime hiccup). Re-run `ocs test`; the deterministic cases are unaffected.
- **Container won't start after a manual docker mess** — `ocs kill` resets all sandbox containers/images/networks (and only those).
- **Where is my session history?** — `<project>/.sandbox/state/opencode/`, mounted at `/home/dev/.local/share/opencode`. `ocs kill` does **not** delete it (only `ocs kill --state` does).
- **I aborted / lost a TUI session — how do I resume it?** — The history is still in `<project>/.sandbox/state/opencode/`. Start a new TUI and continue: `ocs tui my-sandbox -c` (last session) or `ocs tui my-sandbox -s <session-id>`. The name is optional from inside the project (`ocs tui -c`). If the session was killed mid-run, `-c` picks up where it left off.

---

## License & attribution

opencode-sandbox is a fork/derivative of [comsysto/opencode-sandbox](https://github.com/comsysto/opencode-sandbox) (Apache-2.0). This fork is maintained by **kidelo** and the new code was AI-assisted (**Qwen 3.8**). See [README.md → License & attribution](README.md#license--attribution) and `LICENSE`.
