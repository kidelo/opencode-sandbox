# opencode-sandbox

[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg?logo=apache)](LICENSE)
[![stars](https://img.shields.io/github/stars/kidelo/opencode-sandbox?logo=github&label=stars)](https://github.com/kidelo/opencode-sandbox/stargazers)
[![forks](https://img.shields.io/github/forks/kidelo/opencode-sandbox?logo=github&label=forks)](https://github.com/kidelo/opencode-sandbox/network/members)
[![Ollama](https://img.shields.io/badge/Ollama-LLM--provider-6E5BEE?logo=ollama&logoColor=white)](https://ollama.com/)
[![AI-assisted](https://img.shields.io/badge/AI--assisted-development-90A4AE)](AUTHORS.md)

OpenCode is a powerful AI coding assistant — but by default it runs on your host machine with broad access to your environment, shared session state, and a single global configuration for all projects.

**opencode-sandbox** runs OpenCode inside a Docker container, giving each project its own isolated environment:

- 🔒 **Scoped access** — OpenCode sees only one read-write directory, the project **workspace**; its config is mounted **read-only**, and the sandbox's own runtime state is hidden from it
- 🧩 **Per-project configuration** — AI providers, API keys, and model settings are configured independently per project
- 💾 **Persistent session state** — each project retains its own OpenCode history and session between container runs
- 🧹 **Clean environment** — no bleed-over between projects; rebuild any time for a fresh start
- 🛡️ **Network isolation** — every sandbox gets its own dedicated Docker network and an internal firewall; egress is proxy- or firewall-restricted, and the container is dropped to a non-root user
- 🧪 **Verified** — a built-in 9-case security suite (`ocs test`) proves the isolation: unprivileged user, no Docker escape, no root-file read, no system write, no secret read, no egress — **all blocked**

**Quick start**

```bash
git clone https://github.com/kidelo/opencode-sandbox.git
export PATH="…/opencode-sandbox:$PATH"
ocs init my-sandbox && ocs start my-sandbox   # → http://127.0.0.1:4096
```

**Inside the container** there is exactly **one** user read-write directory — `/workspace` (your project's `workspace/`). Everything OpenCode needs besides that is read-only or internal: `opencode.jsonc` (model/provider/permissions) at `/etc/opencode/opencode.jsonc` (**read-only**, so the agent can read its own config but never rewrite it), and the OpenCode session/read-write state tree (persistent, at `/home/dev/.local/share/opencode`). The sandbox's build context and `.sandbox` runtime tree are **never visible** in the container.

The container is based on Debian (python:3.13-slim-bookworm). All software — OpenCode, shell packages, and (in the `full` profile) the dev toolchain — is installed via `apt` during the image build. **No extra toolchain (mise, etc.) needs to be installed on your host, and the container has no access to your Docker daemon.**

> **Want to just start using it?** Read [HOWTO.md](HOWTO.md) — a step-by-step guide covering setup, every way to run OpenCode, the working directories, config, and troubleshooting. This README is the reference and the design rationale.

## Contents

- [Compatibility](#compatibility)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Project setup](#project-setup)
- [Commands](#commands)
  - [`ocs init`](#ocs-init-name) · [`ocs rebuild`](#ocs-rebuild-name) · [`ocs start`](#ocs-start-name) · [`ocs web`](#ocs-web-name) · [`ocs web-auth`](#ocs-web-auth-name)
  - [`ocs terminal`](#ocs-terminal-name) · [`ocs tui`](#ocs-tui-name) · [`ocs run`](#ocs-run-name-prompt) · [`ocs test`](#ocs-test-name)
  - [`ocs clean`](#ocs-clean-name) · [`ocs kill`](#ocs-kill) · [`ocs list`](#ocs-list)
- [Container lifecycle](#container-lifecycle)
- [Network isolation](#network-isolation)
- [Configuration](#configuration--configopencode-sandbox-configyaml)
- [Hooks](#hooks)
- [Project layout](#project-layout)
- [Per-project state](#per-project-state)
- [What changed in this release](#what-changed-in-this-release-vs-the-pre-redesign-repo-state)
- [Changes versus upstream](#changes-versus-upstream)
- [License & attribution](#license--attribution)
- [Remarks](#remarks)

---

## Compatibility

This fork has been tested on the following setup:

| Host OS        | Container Runtime | Status    |
|----------------|-------------------|-----------|
| Linux (Ubuntu) | Docker            | ✅ Tested |

Other combinations will most likely work too — if you try one, please [report your experience](https://github.com/kidelo/opencode-sandbox/issues).

---

## Prerequisites

- A Docker-compatible container runtime (e.g. [Docker](https://docs.docker.com/get-docker/), [Podman](https://podman.io/), [Colima](https://colima.run/))
- [opencode](https://opencode.ai/) if you want to use opencode via a local terminal client instead of the web UI (optional, but recommended for a seamless experience)

---

## Installation

Clone this repository and add the **repository root** to your `PATH`:

```bash
git clone https://github.com/kidelo/opencode-sandbox.git
export PATH="/path/to/opencode-sandbox:$PATH"
```

Add the `export` line to your shell profile (`.zshrc`, `.bashrc`, etc.) to make it permanent.

That's it — the single `ocs` command is now available globally.

---

## Project setup

You address sandboxes **by name** — you never need to `cd` into a project. Create a new sandbox project. New sandboxes always land under the **base sandbox directory** — `./sandboxes/` inside this repository (override with `$OPENCODE_SANDBOX_BASE`) — so all sandboxes live in one place:

```bash
ocs init my-sandbox                      # → ./sandboxes/my-sandbox/
```

`my-sandbox` becomes `./sandboxes/my-sandbox/` and is the sandbox name (lowercase letters, digits, hyphens). It will interactively create `config/opencode-sandbox-config.yaml`, `config/opencode.jsonc`, `opencode-sandbox-pre-start-container.sh` in that directory and build the container — confirming each step before acting.

Then run it — from any directory, by name:

```bash
ocs start my-sandbox                     # one-shot web container, Ctrl-C to stop
# or
ocs tui my-sandbox                       # interactive TUI, no web server
# or
ocs run my-sandbox prompt.md             # one-shot prompt-file run
```

New sandbox projects are **gitignored** by default — they are local to your checkout and not committed to the repo (unless you explicitly `git add` them).

---

## Commands

All functionality is exposed through the single `ocs` command — `ocs <command> <project>` (see `ocs help`). You address sandboxes **by name**, so you never need to `cd` into a project. The `bin/ocs-*` files under the hood are the individual implementations that `ocs` dispatches to; they are not part of the user interface (only the repository root is on your `PATH`, so just `ocs` is reachable).

Most commands take the project **name** as their first argument (e.g. `ocs start my-sandbox`). A few don't: `ocs init <name>` (creates the project), `ocs list`, and `ocs kill`. `ocs run` is special: its first argument is a *name* only when it is a known project — otherwise it is the *prompt* (file or inline) and the project is resolved from the current directory (see `ocs run`).

### `ocs init <name>`

Creates a new sandbox project at `./sandboxes/<name>/` for use with opencode-sandbox.

Interactively creates (each step skipped if already present, default answer is yes):

1. `config/opencode-sandbox-config.yaml` — YAML config pre-filled with `sandbox-name` (set to the project directory name) and `opencode-port`, plus controls for outbound HTTP/HTTPS whitelist, host TCP ports, intranet endpoints, and env var passthrough
2. **Container image profile** — lists the available `config/Dockerfile.*` profiles (minus the reserved `test` one) and writes your choice as a top-level `dockerfile:` key in the config (default: `minimal`)
3. `config/opencode.jsonc` — OpenCode model, provider, and permission config
4. `opencode-sandbox-pre-start-container.sh` — empty hook script sourced before the container starts (see [Hooks](#hooks))
5. Builds the Docker container image (using the profile you picked)

**Scriptable (no prompts):** `ocs init` accepts flags so it can run unattended:

```sh
ocs init -y my-sandbox                                  # accept every default
ocs init -y --dockerfile full my-sandbox                # pick the 'full' profile
ocs init -y --no-build my-sandbox                       # create the project, skip the build
```

- `-y` / `--yes` — accept all defaults; no prompt is ever shown
- `-p` / `--dockerfile <name>` — image profile (default: `minimal`)
- `--no-build` — skip the final image build (run `ocs rebuild <name>` later)
- `-h` / `--help` — show flag help and exit

### `ocs rebuild <name>`

Prepares build artifacts and rebuilds the Docker image. Run this whenever you want a fresh image (new password, updated `config/opencode-sandbox-config.yaml`, etc.).

- Reads `sandbox-name` from `config/opencode-sandbox-config.yaml` and combines it with a short hash of the project root path to form a `SANDBOX_ID` (e.g. `my-project-a3f92c`), then names the container `ocs-<SANDBOX_ID>`
- Creates `<project>/.sandbox/build/` for build artifacts and `<project>/.sandbox/state/` for persistent state
- Generates a random server password saved to `<project>/.sandbox/build/opencode-password` with owner-only permissions
- Parses `config/opencode-sandbox-config.yaml` into derived build artifacts
- Builds the Docker image

### `ocs start <name>`

Starts the sandbox for the current project. Each invocation creates a fresh container (`--rm` ensures it is removed on stop); session state is preserved between runs because the workspace and OpenCode state are mounted volumes.

- Sources `opencode-sandbox-pre-start-container.sh` from the project root, if it exists (see [Hooks](#hooks))
- Forwards whitelisted host environment variables into the container (as configured in `opencode-sandbox-config.yaml`)
- Mounts the project's configured workspace dir (the `workspace:` key, default `workspace/`) at the fixed path `/workspace` inside the container — a stable path, independent of where the project lives on the host
- Mounts any additional directories configured in the `volume-mounts` section of `opencode-sandbox-config.yaml`
- Exposes OpenCode on `http://127.0.0.1:<opencode-port>` (default: `4096`)
- Press `Ctrl+C` to stop and remove the container

### `ocs web <name>`

Opens `http://127.0.0.1:<opencode-port>` in your default browser on macOS or Linux.

Use `ocs web-auth <name>` for authentication or authenticate manually in the browser when prompted:

- **Username:** `opencode`
- **Password:** contents of `<project>/.sandbox/build/opencode-password`

### `ocs web-auth <name>`

Opens the browser with credentials embedded in the URL (basic auth) on macOS or Linux. Use this on first visit to authenticate your browser session.

> **Note:** After authenticating, the page may show a JavaScript error — this is expected. Your session is authenticated; use `ocs web` to open a clean working tab.

### `ocs terminal <name>`

Attaches an OpenCode terminal session to the running web container.

### `ocs tui <name>`

Starts a **one-shot container** and drops directly into the **opencode interactive terminal (TUI)** as the unprivileged `dev` user — no web server involved. The Squid proxy and firewall are applied first (by the entrypoint), so the session is sandboxed exactly like the web one. Leave the session with `Ctrl+D` / `/exit`; the container is removed.

Runs a one-shot `docker run` with a distinct name, so a web container from `ocs start` can keep running in parallel.

### `ocs run [name] <prompt>`

Runs a **one-shot opencode session** (`opencode run`) with a prompt, inside the container. The prompt is either the **contents of a markdown file** or an **inline prompt string**.

```sh
ocs run my-sandbox prompt.md                 # name + prompt file
ocs run my-sandbox "summarise this repo"     # name + inline prompt string
ocs run prompt.md                            # from inside a project (self-hosted pattern)
ocs run "summarise this repo"                # inline, project resolved from the current directory
ocs run my-sandbox prompt.md -f context.md   # extra args pass through to `opencode run`
```

- **First-arg disambiguation:** if the first argument is a known sandbox project it is treated as the *name* and the next argument as the *prompt*; otherwise the first argument is the *prompt* (file or inline) and the project is resolved from the current directory. See `ocs list` for project names.
- The model is **always pinned** to the configured sandbox model (config `model` + `enabled_providers`, plus an explicit `-m` on the CLI) — it cannot be switched in-session.
- `webfetch`/`websearch` are **denied by default** by the opencode config; all web egress additionally has to pass the Squid/iptables firewall.
- A prompt file **inside** the workspace is read in place; a file **outside** is mounted into the container read-only for that run. An **inline** prompt is written to a temp file, mounted read-only for the run, and removed afterward.
- The session's exit code is propagated to the shell.

### `ocs test <name>`

Runs the sandbox security test suite. **No running container needed** — `ocs test` uses its own one-shot test container, runs the checks inside it, and removes it again when done.

`ocs test` builds and runs from the **reserved** `config/Dockerfile.test` profile (a network-analysis image: `nmap`, `tcpdump`, DNS/traceroute tools, `python3`, `jq`). It is stored under its own tag `ocs-<SANDBOX_ID>-test`, so running the suite **never changes** the project's working image (built from `minimal` or `full`). The test image is cached for a fast re-run; it is removed on a fail/crash and by `ocs kill`.

The suite has two kinds of checks:
- **Deterministic** — asserts the container is not running as root, that `/etc/shadow` and other sensitive files are unreadable, that `/usr` is not writable, that **no docker escape channel exists** (no socket, no `docker`/`podman` CLI), that the sandbox is L2-isolated on its dedicated network, and that direct connections to endpoints not in `intranet-endpoints` / `host-ports` are dropped by the firewall.
- **AI-agent red-team** — drives the configured model (via `opencode run`) to actively try six escapes (proxy bypass, direct egress, privilege escalation, root-file read, system write, secret read). The agent writes a JSON report to `/tmp` inside the container; the runner then fails if the agent reports any attack as `succeeded`.

If the AI-agent case cannot reach the configured model endpoint (e.g. the Ollama server's `ip:port` is not in `intranet-endpoints`), it SKIPs with a hint; the deterministic cases still provide the security signal.

> **Note:** On a **pass** the test image (`ocs-<SANDBOX_ID>-test`) is kept so a re-run is fast; on a **fail** (or crash) it is removed so only known-good builds remain. The working image (`ocs-<SANDBOX_ID>`) is untouched either way. `ocs clean` / `ocs kill` remove the test image too.

### `ocs clean <name>`

**Nuclear per-project cleanup** — removes *everything* this project created on this host, but leaves the project's source files (`config/`, `prompt.md`, `app/`, `data/`, …) untouched. Idempotent.

> **Tip:** `ocs clear <name>` is an alias for `ocs clean <name>` — same effect, easier to remember.

Removes:
- All containers of this project (running **and** stopped) — `ocs-<SANDBOX_ID>` and any `-run-$$` / `-tui-$$` / `-test-$$` variants
- Both images of this project — `ocs-<SANDBOX_ID>` (working: `minimal` or `full`) **and** `ocs-<SANDBOX_ID>-test` (the reserved test profile)
- The dedicated Docker network — `ocs-net-<SANDBOX_ID>`
- Both on-disk trees inside the project — `<project>/.sandbox/build/` and `<project>/.sandbox/state/`

```sh
ocs clean my-project   # everything for my-project (never touches another project)
```

After `ocs clean`, the project is back to "never been built on this host". `ocs rebuild <name>` restores the image, and `ocs start` / `ocs tui` / `ocs run` work again — no other steps needed.

> **Note:** `ocs clean` is scoped to exactly one project — use it when you want to *wipe one project's sandbox* (e.g. you are discarding it, or you hit a stateful build problem). For *cross-project* cleanup (every sandbox on this host) use `ocs kill` instead.

### `ocs kill`

Cleans up everything the sandbox system created on this host — useful after a crash, a hard abort, or to fully remove a sandbox:

- All leftover sandbox **containers** (running or stopped)
- All sandbox **images** (`ocs-*`)
- All dedicated sandbox **networks** (`ocs-net-*`)

```sh
ocs kill              # all projects' sandbox artifacts
ocs kill my-project   # only artifacts whose name contains 'my-project'
ocs kill --purge my-project   # also delete the project's disposable <project>/.sandbox/build/
ocs kill --state my-project   # also delete .sandbox/build/ and .sandbox/state/ (session)
```

Both `ocs kill` and `ocs clean` match the current `ocs-` / `ocs-net-` names **and** the legacy `opencode-sandbox-` / `opencode-sandbox-net-` names from before the rename, so pre-rename artifacts are still cleaned. Only objects with those name families are ever touched — all other containers, images, and networks in your Docker environment (including those of other projects that don't use this tool) are left completely alone. The command is idempotent: running it with nothing left to do simply reports nothing removed.

> **Note:** `ocs kill` removes the **image**, so `ocs rebuild` is required before starting again. The per-project state directory (`<project>/.sandbox/state/`) is **not** touched by a plain `kill` — session history survives. Add `--purge` to also remove the disposable build dir, or `--state` to remove both the build dir and the session.

### `ocs list`

Lists every sandbox project under `./sandboxes/` (the base directory; override with `$OPENCODE_SANDBOX_BASE`). Does not need a project argument and does not start a container:

```sh
ocs list              # → my-sandbox, another-sandbox, …
```

Use it to discover the name to pass to other `ocs <command> <name>` invocations.

## Container lifecycle

| Situation | Command |
|---|---|
| First time setup | `ocs init my-sandbox` then `ocs start my-sandbox` |
| Daily use | `ocs start my-sandbox` |
| After changing `config/Dockerfile.<profile>` | `ocs rebuild my-sandbox` then `ocs start my-sandbox` |
| After changing `config/opencode-sandbox-config.yaml` | `ocs rebuild my-sandbox` then `ocs start my-sandbox` |
| Interactive session (TUI, no web) | `ocs tui my-sandbox` |
| One-shot from a prompt file | `ocs run my-sandbox your/prompt.md` |
| Verify sandbox security | `ocs test my-sandbox` (its own test image; no web session needed) |
| List sandbox projects | `ocs list` |
| Wipe one sandbox completely (image + network + state) | `ocs clean my-sandbox` |
| Stop the web container | `Ctrl+C` in the `ocs start my-sandbox` terminal (container is removed) |
| Full cleanup after a crash/abort | `ocs kill` or `ocs kill my-sandbox` (containers + images + networks) |

> **Note:** There is **no long-running container**: the only persistent artifact is the Docker **image** (plus one dedicated Docker network per sandbox). Each `ocs start` run creates a fresh container that is removed on stop. Session state is preserved between runs via mounted volumes (workspace and `<project>/.sandbox/state/opencode/`). `ocs rebuild` rebuilds the image but does not affect the mounted state.

---

## Network isolation

Isolation works on two levels:

**1. Own Docker network (L2 separation).** Every sandbox container runs on a dedicated Docker network named `ocs-net-<SANDBOX_ID>`, created automatically on first use. All sandboxes get their addresses from the range configured under `sandbox-network-cidr` (default **`10.77.0.0/16`**, so containers live on `10.77.x.x`); each sandbox receives its own `/24` inside that range. Consequences:

- Your other Docker containers (which stay on the default bridge or their own networks) can neither reach nor be probed by the sandbox — and are completely unaffected by sandbox activity.
- Sandboxes of different projects can never reach each other.
- All runs of the same sandbox (web + parallel TUI) share this one network.

**2. Internal firewall (egress control).** The container runs a [Squid](https://www.squid-cache.org/) proxy that restricts outbound HTTP/HTTPS traffic to an explicit whitelist. `iptables` rules inside the container use a default-deny outbound policy and allow only loopback traffic, established connections, Squid's own DNS + HTTP/HTTPS egress, direct connections to `host-ports`, and direct connections to `intranet-endpoints`. OpenCode (and any tools it spawns) must go through the proxy for any domain not listed above.

All outbound traffic is routed via the proxy automatically through the standard `http_proxy` / `https_proxy` environment variables set by the container entrypoint.

> **Notes:** The container requires the `NET_ADMIN` Docker capability for `iptables` — this is added automatically by the run commands. The sandbox container can **not** talk to the host Docker daemon: no socket is mounted and no `docker`/`podman` CLI is installed.

---

## Configuration — `config/opencode-sandbox-config.yaml`

The `config/opencode-sandbox-config.yaml` file (in the `config/` directory of your project) controls the project name, OpenCode HTTP port, outbound network access, and environment variables. It is safe to commit (alongside `config/opencode.jsonc`).

> **Note:** Only a narrow YAML subset is supported: top-level keys, one-level-deep list items (`- value`), and one-level-deep map entries (`key: value`). Anchors, multi-line strings, nested structures, and other YAML features are not supported.

```yaml
sandbox-name: my-project
opencode-port: 4096
dockerfile: full              # image profile -> config/Dockerfile.full (default: minimal)
workspace: workspace          # the single rw dir (default); mounted at /workspace

http-domain-whitelist:      # outbound HTTP/HTTPS allowed via the proxy — leave empty to deny all
  # - .github.com

host-ports:                   # disabled by default — add host TCP ports only if needed
  # - 5432
  # - 6379

intranet-endpoints:
  - 10.0.0.5:3306
  - 192.168.1.10:8080

env-passthrough:
  ANTHROPIC_API_KEY: ANTHROPIC_API_KEY
  GH_TOKEN: MY_PROJECT_GH_TOKEN

env:
  GITHUB_REPOSITORY: my-org/my-repo
```

**`sandbox-name`** — human-readable project identifier (required):
- Committed to the repository as a stable label for the project
- At runtime, combined with a short hash of the absolute project root path to form `SANDBOX_ID` (e.g. `my-project-a3f92c`), making collisions between multiple checkouts of the same repo unlikely
- `SANDBOX_ID` is the unique name for all container artifacts: image (`ocs-<SANDBOX_ID>`), container (`ocs-<SANDBOX_ID>`), dedicated network (`ocs-net-<SANDBOX_ID>`), and the in-project state/build dirs (`.sandbox/state/`, `.sandbox/build/`)
- Set automatically by `ocs init` using the directory basename
- You may rename it, but a rebuild is required and the old in-project `.sandbox/` tree will be orphaned

**`sandbox-network-cidr`** — the IP range all sandbox containers draw from:
- Defaults to `10.77.0.0/16` when omitted (containers live on `10.77.x.x`)
- Must be a private IPv4 CIDR with prefix 8–24 (prefix >24 cannot contain a full `/24`) (e.g. `10.77.0.0/16` or `10.20.0.0/14`)
- Each sandbox gets its own dedicated `/24 inside the range`; sandboxes of other projects stay L2-separated from it
- Used when you need the sandboxes to be reachable/visible in a specific private range (e.g. by on-prem services)
- A rebuild is required after changing this setting

**`opencode-port`** — HTTP port for the OpenCode server and host clients:
- Defaults to `4096` when omitted
- Must be an integer from `1` through `65535`
- Used by the server inside the container, the host port mapping, `ocs terminal`, `ocs web`, and `ocs web-auth`
- A rebuild is required after changing this setting
- If two sandboxes on the same host use the same `opencode-port`, the second web container start fails with "port is already allocated" — use distinct `opencode-port` values per project when running several in parallel (or use the one-shot `ocs run` / `ocs tui` modes, which publish no port at all)

**`dockerfile`** — the container image profile to build from:
- Selects which `config/Dockerfile.<name>` file `ocs rebuild` builds: the `minimal` profile (harness + `python3`, the default) or the `full` profile (full dev toolchain: build tools + a large `pip` data/office/PDF/OCR/sci stack)
- `ocs init` lists the available profiles (the `config/Dockerfile.*` files, excluding the reserved `test` one) and writes your choice here
- The `test` profile (`config/Dockerfile.test`, a network-analysis image) is reserved for `ocs test` and **cannot** be selected by a project
- A rebuild is required after changing this setting

**`workspace`** — the single user read-write directory, mounted at `/workspace`:
- A project subdirectory holding **source code and data together** (they may be the same directory — no separate read-only input for the user is provided)
- Defaults to `workspace/`; a new project gets `workspace/` created by `ocs init`. Set `workspace: .` to make the **entire project** the workspace (this is what this repository does for itself)
- Inside the container this is always `/workspace` — a fixed, easy path, independent of where the project lives on the host
- A rebuild is required after changing this setting

**`http-domain-whitelist`** — domains allowed through the Squid HTTP/HTTPS proxy:
- **Empty by default** — no domain is allowed until you add one. Start from an empty list and open only what the project needs (least privilege). The bundled `config/opencode-sandbox-config.yaml` ships with no active entries.
- A leading dot matches the domain **and** all its subdomains (e.g. `.github.com` allows `github.com`, `api.github.com`, `raw.githubusercontent.com`, etc.)
- Without a leading dot, only the exact domain is matched (e.g. `api.anthropic.com` does **not** allow `bedrock.anthropic.com`)
- When in doubt, use the leading-dot form to avoid hard-to-debug connection failures
- A rebuild is required after adding or removing entries

**`host-ports`** — TCP ports on the host machine the container may connect to directly (bypasses the proxy):
- **Disabled by default** — the list ships empty, so the container cannot reach any host port until you add one.
- Use this for databases, local dev servers, and other services running on the host
- The host is reachable via `docker.host` (injected automatically at container start) — use this hostname instead of `localhost`

**`intranet-endpoints`** — `ip:port` endpoints the container may connect to directly (bypasses the proxy):
- Format is `ipv4:port` per line, e.g. `10.0.0.5:3306` or `192.168.1.10:8080`
- Use this for on-premises / intranet services not running on the host (internal databases, APIs, registries, …)
- Each endpoint is allowlisted by the firewall and added to `no_proxy`, so clients connect to it directly without going through Squid
- A rebuild is required after adding or removing entries

**`env-passthrough`** — host environment variables to forward into the container:
- Format is `CONTAINER_VAR: HOST_VAR` — use the same name on both sides for a simple passthrough, or different names to rename
- Values are read from the host shell at container start time; variables not set on the host are skipped and noted in the startup summary
- Use this for secrets and credentials — values never touch a file
- A rebuild is required after adding or removing entries

**`env`** — static environment variables set directly in the container:
- Use this for non-secret project context that is safe to commit: repo name, project identifiers, feature flags, etc.
- Values are literal — no shell expansion
- A rebuild is required after adding or removing entries

`ocs rebuild` reads this file to generate derived build artifacts — **a rebuild is required after changes**. The file is required; `ocs rebuild` fails if it is missing.

---

## Hooks

### `opencode-sandbox-pre-start-container.sh`

If a file named `opencode-sandbox-pre-start-container.sh` exists in the project root, `ocs start` will **source** it before starting the container. Because it is sourced (not executed as a subprocess), any `export` statements take effect in the calling shell and are picked up by `env-passthrough`.

Typical uses:
- Refresh short-lived credentials (AWS SSO, GCP, Azure, Vault, …)
- Derive env vars from the host at start time

`ocs init` creates this file for you (empty, executable). If it contains secrets, add it to `.gitignore`:
```
opencode-sandbox-pre-start-container.sh
```

**Example — refresh AWS SSO credentials and forward them into the container:**

`opencode-sandbox-pre-start-container.sh`:
```bash
#!/usr/bin/env bash
aws sso login --profile my-profile
eval "$(aws configure export-credentials --profile my-profile --format env)"
```

`config/opencode-sandbox-config.yaml`:
```yaml
env-passthrough:
  AWS_ACCESS_KEY_ID: AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY: AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN: AWS_SESSION_TOKEN
```

---

## Project layout

```
opencode-sandbox/
├── ocs                         # Single entry point for all commands (init/rebuild/start/tui/run/web/terminal/test/clean/kill/list)
├── bin/
│   ├── ocs-init                # Initialize a project under ./sandboxes/ (repo-local)
│   ├── ocs-rebuild-container   # Build the Docker image
│   ├── ocs-start-container     # Start the web container (opencode web)
│   ├── ocs-interactive         # One-shot container with the opencode TUI (no web server)
│   ├── ocs-run                 # One-shot `opencode run` from a markdown prompt file
│   ├── ocs-terminal            # Attach a terminal session to the web server
│   ├── ocs-web                 # Open the web UI
│   ├── ocs-web-auth            # Open the web UI with authentication
│   ├── ocs-test                # Run the security test suite (starts its own container)
│   ├── ocs-clean               # Nuclear per-project cleanup (containers + images + network + state)
│   ├── ocs-kill                # Remove sandbox containers, images, and networks
│   └── shared                  # Shared configuration, utilities, and guards (sourced by the ocs-* scripts)
├── config/                     # Project config — the single source; copied into target projects by ocs init (except the Dockerfiles)
│   ├── Dockerfile.minimal      #   image profile: harness + python3 (default)
│   ├── Dockerfile.full         #   image profile: full dev toolchain (pip data/office/sci stack)
│   ├── Dockerfile.test         #   image profile: reserved for `ocs test` (network-analysis suite)
│   ├── opencode-sandbox-config.yaml
│   └── opencode.jsonc
├── docker/                     # Container runtime files (copied into the build context by ocs-rebuild-container)
│   ├── entrypoint.sh           #   squid + firewall + opencode start
│   └── squid.conf              #   proxy whitelist config
├── sandboxes/                  # New sandbox projects (created by ocs init) — gitignored by default
├── test/
│   ├── common.sh               # Helpers shared by test cases (pass/fail, tcp_connect)
│   └── cases/                  # Individual security test cases (01-09)
├── README.md                   # This file — reference & design rationale
├── HOWTO.md                    # Step-by-step setup and run guide
├── AGENTS.md                   # Conventions for contributors working on the sandbox itself
├── AUTHORS.md                  # Upstream (comsysto) + fork (kidelo) attribution
└── LICENSE                     # Apache-2.0
```

## Per-project state

Each project gets its own isolated container named `ocs-<SANDBOX_ID>`. The `SANDBOX_ID` is derived at runtime from the `sandbox-name` in the config file and a short hash of the project root path, so multiple checkouts of the same repo get distinct IDs (used only for the container/image/network names). The on-disk state and build context live **inside the project**, under `.sandbox/`, split into two trees by nature — `.sandbox/build/` (disposable build context + log, regenerated by every `ocs rebuild`) and `.sandbox/state/` (persistent session + subnet binding, survived across rebuilds):

```
<project>/.sandbox/
├── build/                       # Disposable build context (regenerated on rebuild)
│   ├── opencode-password        # Generated server password (owner-only, root:root)
│   ├── opencode-port            # Validated OpenCode HTTP port
│   ├── sandbox-network-cidr.txt # Configured network range (e.g. 10.77.0.0/16)
│   ├── squid.conf               # Copied from the sandbox repo (docker/squid.conf)
│   ├── squid-whitelist.txt      # Extracted from http-domain-whitelist
│   ├── host-ports.txt           # Extracted from host-ports
│   ├── intranet-endpoints.txt   # Extracted from intranet-endpoints
│   ├── env-passthrough.txt      # Extracted from env-passthrough
│   ├── env.txt                  # Extracted from env
│   ├── volume-mounts.txt        # Extracted from volume-mounts
│   ├── entrypoint.sh            # Copied from the sandbox repo (docker/entrypoint.sh)
│   └── docker-build.log         # Docker build output (created during build)
└── state/                       # Persistent (survives a rebuild)
    ├── opencode/                # OpenCode session/history (mounted into the container)
    └── sandbox-network-map      # Sandbox → /24 subnet binding (deterministic, written by rebuild)
```

OpenCode state (including session history, configuration, and cache) is persisted across container restarts by mounting `<project>/.sandbox/state/opencode/` as `/home/dev/.local/share/opencode` inside the container.

`.sandbox/` is gitignored as a whole (see `.gitignore`) — neither the disposable build context (which holds the random `opencode-password`) nor the session history is ever committed. `ocs rebuild` overwrites the `build/` tree in place; `ocs kill --purge <name>` removes `build/`, and `ocs kill --state <name>` also removes `state/`.

---

## What changed in this release (vs the pre-redesign repo state)

The container now exposes exactly three mounts to the agent. Only the first is a user rw dir; the others are neutral (state, read-only config). `.sandbox` was previously visible in the mounted 1:1 host view and could be rewritten; it is now hidden.

| Area | Before | Now |
|---|---|---|
| **Workspace** | The whole project root mounted 1:1, read-write, at its real host path (e.g. `/home/you/proj -> /home/you/proj`) | **A single rw dir, always `/workspace`** (`workspace:` key, default `workspace/` — see "Configuration" above). Source code **and** data live in the same place (no separate "input" dir) |
| **`opencode.jsonc` (model/provider/permissions)** | Mounted read-write via `OPENCODE_CONFIG -> <project>/config/opencode.jsonc` — the agent could rewrite it (weaken its own deny list / swap the model endpoint) | Mounted **read-only** at `/etc/opencode/opencode.jsonc`; `OPENCODE_CONFIG` points at that path — the agent **reads it but cannot rewrite it**; a change still takes effect without a rebuild (it is the live file) |
| **`.sandbox/` visibility** | Visible and writable inside the container (part of the 1:1 mount) | **Never visible.** For a normal project it is outside the mounted `/workspace/` subdirectory to begin with. For the self-hosted case (`workspace: .`) `build_run_flags` masks `.sandbox` with an empty read-only dir at `/workspace/.sandbox` |
| **Squid** | Started unconditionally on every door, even when `http-domain-whitelist` was empty | **Started only when `http-domain-whitelist` is non-empty**. When empty, no squid process, no proxy env, and egress is firewall-only (still default-deny). Saves one root process and the proxy env in the "no external server needed" case |
| **Capabilities** | `--cap-drop=ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID` | Same set, now assembled by `compute_cap_flags()` in `bin/shared` (the single source) instead of duplicated in every door. `SETUID`/`SETGID` are required by `gosu dev` (the root→dev user drop every door performs), not only by squid — they stay unconditional |
| **In-container path** | Same path as on the host (1:1) | Fixed `/workspace` for user files; fixed `/etc/opencode/opencode.jsonc` for config; fixed `/home/dev/.local/share/opencode` for the persistent opencode state |
| **`ocs test` visibility** | Mounted the whole repo root read-only (so test cases under `SANDBOX_HOME/test/cases` could be found) — this leaked `.sandbox` and the rest of the host project into the test container | Mounts **only** `<repo>/test/` read-only. Cases still run because they are addressed at the `SANDBOX_HOME`-relative path they were invoked at |
| **`bin/shared` new API** | `build_run_flags` assembled `--cap-*` inline per door | New `proxy_enabled()`, `compute_cap_flags()`, `SANDBOX_WORKSPACE_DIR`, `SANDBOX_RUNTIME_BASE`; `build_run_flags` populates `CAP_FLAGS` alongside `RUN_FLAGS`/`RUN_LOG` so every door reuses one place |
| **Self-hosted repo (this one)** | Mounted the repo 1:1 — agent could edit `bin/`, `config/`, `.sandbox/` | `workspace: .` (the whole repo **is** the workspace) — expected and intended for a self-host; `.sandbox/` is masked in-container (above). Runtime tree remains *inside* the project (gitignored via the `.sandbox` entry) — it is *never* visible to the agent but lives in a stable, `ocs clean`-able location |

Items **unchanged** from the pre-redesign state: the `ocs` dispatcher surface, image profiles (`minimal` / `full` / `test`), the `sandbox-network-cidr` per-sandbox `/24`, `intranet-endpoints`, `env-passthrough` / `env`, the build-once one-shot container lifecycle, and `ocs kill` / `ocs clean`.

---

## Changes versus upstream

This repository is a **fork** of [comsysto/opencode-sandbox](https://github.com/comsysto/opencode-sandbox). The fork diverges from upstream in the following areas (all are additive to, or harden, the upstream model):

| Area | Upstream | This fork |
|---|---|---|
| **CLI entry point** | One `ocs-*` command per action, all added to `PATH` | **Single `ocs` dispatcher** (`ocs init / rebuild / start / tui / run / web / web-auth / terminal / test / clean (clear alias) / kill`) at the repository root — one command to learn, the `bin/ocs-*` files become internal implementations |
| **Project location** | `ocs-init` runs in place (project lives where `pwd` points) | **New projects always land under `./sandboxes/<name>/`** (repo-local; override via `$OPENCODE_SANDBOX_BASE`) so all sandboxes sit in one directory |
| **Container runtime in image** | (not documented upstream) | **No `docker`/`podman` CLI, no host-socket mount** in any profile — a defense-in-depth removal of the strongest escape vector; security test **06 hard-fails** if any runtime ever re-appears in the image |
| **Network model** | Containers on the shared default Docker bridge | **Per-sandbox dedicated Docker network** `ocs-net-<SANDBOX_ID>`, isolated in both directions, L2-separated from other host containers **and** from each other |
| **Network IP range** | (n/a) | **Configurable range** `sandbox-network-cidr` (default `10.77.0.0/16`); each sandbox gets a stable, deterministic `/24` inside it |
| **Image & toolchain** | `mise`-based image (a `mise.toml` + single `Dockerfile`) | **`apt`/`pip`-based image, no `mise`** — nothing but the container runtime is needed on the host; selectable profiles `Dockerfile.minimal` (default), `Dockerfile.full` (dev/data toolchain), reserved `Dockerfile.test` (used only by `ocs test`) |
| **Workspace & config mounts** | Project mounted at its **same absolute host path** inside the container | **Fixed `/workspace` (rw)** — the single user rw dir — plus `opencode.jsonc` at **`/etc/opencode/opencode.jsonc` (read-only)**, so the agent can read its own config but never rewrite it; the sandbox's `.sandbox` runtime tree is **masked** out of the workspace |
| **State location** | Global host dir `~/.opencode-sandbox/<SANDBOX_ID>/` | **In-project** `.sandbox/{build,state}/` (opencode state tree persistent across runs; gitignored; removed by `ocs clean`/`ocs kill`) |
| **Container lifecycle** | Long-running web container as the norm | **Build-once, one-shot runs** — the image is the only persistent artifact; web / TUI / one-shot / test are all fresh `docker run`s that clean themselves up |
| **Run modes** | Web UI (`ocs start`) | Added **`ocs tui`** (TUI) and **`ocs run`** (markdown prompt file **or inline prompt string**) one-shot modes |
| **Security** | Manual | **`ocs test`** automated suite (deterministic assertions + an AI-agent red-team) that runs its own one-shot container from the reserved `Dockerfile.test` profile (image `ocs-<ID>-test`) and **removes only the test image on FAIL** — the working image is never clobbered |
| **Cleanup** | Manual `docker rm` | **`ocs kill`** — idempotent removal of all sandbox containers, images, and networks without touching anything else |
| **Config layout** | Config at project root; templates in `init-templates/` | **`config/` single source of truth**, plus `docker/` for runtime files and `bin/shared` for the shared library — no duplicated templates |
| **OpenCode config resolution** | Relies on `opencode.jsonc` in the workspace cwd | Sets **`OPENCODE_CONFIG`** to the read-only-mounted single-source file — so opencode always uses `config/opencode.jsonc`, and the agent **cannot swap in its own** by dropping a file in the workspace |
| **Report location** | `security-report.json` in the workspace | Agent report written to **`/tmp`** inside the container — no workspace clutter |
| **Compatibility claim** | macOS/Colima + Podman + Linux/Docker "tested" | **Linux (Ubuntu) + Docker tested**; other platforms unverified for this fork |

Items *inherited* unchanged from upstream include the Squid + `iptables` egress firewall (default-deny outbound, Squid started only when a domain whitelist is present), `host-ports` / `intranet-endpoints` direct-egress allowlists, `env-passthrough` / `env`, `volume-mounts`, the per-start `opencode-sandbox-pre-start-container.sh` hook, the OpenCode basic-auth web UI, and the `sandbox-name` / `SANDBOX_ID` naming scheme.

If you are forking **this** fork rather than upstream, use the URLs in this repo (`github.com/kidelo/opencode-sandbox`).

---

## License & attribution

opencode-sandbox is a **fork/derivative** of the [comsysto/opencode-sandbox](https://github.com/comsysto/opencode-sandbox) project, which is distributed under the **Apache License 2.0**.

- **Upstream origin:** `comsysto/opencode-sandbox` (Apache-2.0). Upstream copyright is preserved per the Apache-2.0 terms and in the `LICENSE` file.
- **This fork:** maintained by **kidelo** (`github.com/kidelo/opencode-sandbox`).
- **New/changed code:** developed with AI assistance (**Qwen 3.8**, OpenAI-compatible endpoint); contributions remain licensed under the same Apache-2.0 terms.

Full attribution of upstream authors and fork maintainers is in [AUTHORS.md](AUTHORS.md).

The Apache-2.0 `LICENSE` file is the governing license for this repository and applies to both the upstream-derived and fork-authored portions. See [HOWTO.md → License & attribution](HOWTO.md#license--attribution) for a short summary.

---

## Remarks

OpenCode Sandbox is not built by the OpenCode team and is not affiliated with OpenCode.
