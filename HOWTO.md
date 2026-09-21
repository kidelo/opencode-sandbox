# How to — set up a sandbox and run OpenCode in it

This guide walks through the full lifecycle: installing the tool, initialising one project, and the different ways to run OpenCode inside its sandbox container. For the reasoning, design decisions and developer conventions see [AGENTS.md](AGENTS.md); for the option-by-option reference see [README.md](README.md).

> **Who this is for:** a developer who wants to run OpenCode (the AI coding assistant) for *a specific project* inside an isolated Docker container, scoped to that project's files and a controlled network.

---

## 1. Prerequisites

- A Docker-compatible runtime (Docker, Podman, or Colima). This project was tested on Linux with Docker.
- A network that can reach `opencode.ai` (the installer) and your model endpoint (e.g. an Ollama server) — both are listed in the sandbox config, see `config/opencode-sandbox-config.yaml`.
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
2. Creates the per-project tree `<project>/.sandbox/{build,state}/` and generates a random web-server password in `build/opencode-password`.
3. Extracts the config into build artifacts: domain whitelist, host ports, intranet endpoints, env passthrough, volume mounts — and the sandbox network CIDR range.
4. Builds the Docker image `ocs-<SANDBOX_ID>` from the profile named by the `dockerfile:` key (e.g. `config/Dockerfile.minimal` → `Dockerfile.minimal`, `Dockerfile.full` → `Dockerfile.full`), plus `docker/entrypoint.sh` and `docker/squid.conf`.

> **Run this again whenever** `config/opencode-sandbox-config.yaml`, `config/opencode.jsonc`, `config/Dockerfile.<profile>` or `docker/entrypoint.sh` change. The image is the **only** persistent artifact — there is no long-running sandbox container to keep updated.

---

## 5. Running OpenCode — your options

There are four ways to run, all of which use the same image and the same sandbox (firewall + network isolation). You address the project **by name**, e.g. `my-sandbox`:

| Goal | Command | Container lifetime |
|---|---|---|
| **Web UI** (browser) | `ocs start my-sandbox` then `ocs web my-sandbox` | lives while the terminal is open |
| **TUI** in your terminal | `ocs tui my-sandbox` | one-shot, dies when you `/exit` |
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

### 5b. Interactive TUI — `ocs tui <name>`

Drops straight into the **opencode terminal (TUI)** as the `dev` user in a one-shot container. Squid + firewall are applied first (by the entrypoint), so the session is sandboxed exactly like the web one.

```bash
ocs tui my-sandbox
```

Leave with `Ctrl+D` or `/exit`; the container is removed automatically. No web server is started.

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

---

### 5d. Security test — `ocs test <name>`

Runs the sandbox security suite in its own one-shot container (no web container needed) and always removes it afterwards. It builds from the reserved `config/Dockerfile.test` profile (a network-analysis image: `nmap`, `tcpdump`, DNS tools, `python3`, `jq`) under its own tag `ocs-<SANDBOX_ID>-test`, so it does **not** touch the project's working image (built from `minimal` or `full`) — and the test image is removed automatically when `ocs test` exits:

```bash
ocs test my-sandbox
```

It checks (deterministic + an AI-agent red-team) that egress is blocked, no sensitive files are readable, no Docker escape channel exists, and the sandbox is on its own isolated network on the configured IP range.

> **If a case fails** (or the run is interrupted), `ocs test` **removes the test image** (`ocs-<SANDBOX_ID>-test`) so only known-good builds remain. Your working image is untouched.

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
```

- **`http-domain-whitelist`** — domains the Squid proxy will forward. **Empty by default — nothing is allowed until you add a domain.** A leading dot covers subdomains.
- **`host-ports`** — for databases/servers on the host machine. **Disabled by default (empty)**; add ports only if needed. Use the hostname `docker.host` (not `localhost`) inside the container.
- **`intranet-endpoints`** — for on-prem services on other machines. This must include your model endpoint or the agent cannot reach it (see `ocs test` SKIP hint). Endpoints are `ip:port` **by design** — the agent's own DNS is denied by default (`agent-dns: deny`), so nothing inside the container may rely on hostname resolution for endpoints.
- **`agent-dns`** — `deny` (default) or `allow`. `deny` is the secure path (no DNS exfil/C2 channel); `allow` re-opens the resolver for the agent — only turn this on when an endpoint must be a hostname (e.g. model `baseURL`).
- **`env-passthrough` / `env`** — credentials (via passthrough, never a file) and non-secret context (via `env`).
- **`sandbox-network-cidr`** — the private range all your sandboxes draw from; each sandbox gets its own `/24` inside it, L2-separated from the others.

`config/opencode.jsonc` sets the model, provider (`baseURL` of your Ollama server) and OpenCode permissions (`webfetch` / `websearch` denied by default). Change it if you point at a different model.

> **Any change to `config/…` requires a rebuild:** `ocs rebuild`.

---

## 8. Hooks

If `opencode-sandbox-pre-start-container.sh` exists in the project root, `ocs start` **sources** it (not executes) before starting the container. Use it to refresh short-lived credentials:

```bash
#!/usr/bin/env bash
aws sso login --profile my-profile
eval "$(aws configure export-credentials --profile my-profile --format env)"
# export AWS_ACCESS_KEY_ID / _SECRET_ACCESS_KEY / _SESSION_TOKEN so env-passthrough picks them up
```

If it contains secrets, add it to `.gitignore`.

---

## 9. Daily / maintenance commands

| Situation | Command |
|---|---|
| First-time setup | `ocs init my-sandbox` then `ocs start my-sandbox` |
| Daily use (web) | `ocs start my-sandbox` then `ocs web my-sandbox` |
| Daily use (TUI) | `ocs tui my-sandbox` |
| One-shot task | `ocs run my-sandbox prompt.md` |
| After a config/Dockerfile change | `ocs rebuild my-sandbox` then your run command |
| Verify sandbox security | `ocs test my-sandbox` |
| List sandbox projects | `ocs list` |
| Wipe one sandbox completely (image + network + state) | `ocs clean my-sandbox` |
| Full cleanup of all sandboxes on this host | `ocs kill` |
| Stop the web container | `Ctrl+C` in the `ocs start my-sandbox` terminal |
| Clean up after a crash / hard abort (all sandboxes) | `ocs kill` |

---

## 10. Troubleshooting

- **"port is already allocated"** — two sandboxes are using the same `opencode-port`. Use different ports, or switch to the portless one-shot modes.
- **Agent case SKIPs in `ocs test`** — the model endpoint (your Ollama `ip:port`) is not reachable from the container. Add it to `intranet-endpoints` in `config/opencode-sandbox-config.yaml` and rebuild.
- **The agent cannot resolve a hostname (DNS "no answer"/timeout)** — expected with the default `agent-dns: deny` (the DNS exfil/C2 channel is closed). Two options: address the endpoint by IP (`intranet-endpoints: - ip:port`, and give the model `baseURL` an IP), or set `agent-dns: allow` in the config and rebuild if you accept the DNS exfil risk.
- **A test case FAILed and the image vanished** — by design. `ocs rebuild` brings it back.
- **Container runs out of memory / is killed (OOM) or feels CPU-limited** — every sandbox runs with host-DoS guards by default: `--memory=4g --cpus=2.0 --pids-limit=256 --security-opt=no-new-privileges:true` (see README → Network isolation). Raise the values in `bin/shared` (`build_run_flags`) and start again — no rebuild needed.
- **`ocs test` case 11 says "peer container not started"** — the runner could not bring up the second isolation-check container (e.g. image missing or runtime hiccup). Re-run `ocs test`; the deterministic cases are unaffected.
- **Container won't start after a manual docker mess** — `ocs kill` resets all sandbox containers/images/networks (and only those).
- **Where is my session history?** — `<project>/.sandbox/state/opencode/`, mounted at `/home/dev/.local/share/opencode`. `ocs kill` does **not** delete it (only `ocs kill --state` does).

---

## License & attribution

opencode-sandbox is a fork/derivative of [comsysto/opencode-sandbox](https://github.com/comsysto/opencode-sandbox) (Apache-2.0). This fork is maintained by **kidelo** and the new code was AI-assisted (**Qwen 3.8**). See [README.md → License & attribution](README.md#license--attribution) and `LICENSE`.
