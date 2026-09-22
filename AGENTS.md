# AGENTS.md

See [README.md](README.md) for project overview, key files, commands, and per-project state layout.

README.md is intended for end users (developers setting up or using the sandbox). It may explain how things work internally, but must not document development practices — those belong here in AGENTS.md.

Every change to the user experience (new commands, changed behaviour, new files created in target projects, etc.) must be reflected in README.md.

## Reasoning / execution style

*** Prefer low-to-medium reasoning effort and straightforward solutions. Do not overthink, over-engineer, or add unnecessary abstraction. For routine changes, use the simplest solution that
is correct, maintainable, and consistent with the existing project. Escalate to deeper analysis only when the task is genuinely ambiguous, risky, or technically complex ***

## Execution environment

This project uses itself as its own sandbox — the AI agent runs **inside the opencode-sandbox container** for this repository. This means:

- The single user rw dir is the project's **workspace** (`workspace:` key, default `workspace/`; the repo uses `.`), mounted at the fixed path `/workspace`. `.sandbox/` (build context + opencode state) is gitignored and — for the self-hosted repo where it sits inside the mounted tree — is **masked in-container with an empty read-only dir** so it never appears in `/workspace`
- `config/opencode.jsonc` (model/provider/permissions) is mounted **read-only** at `/etc/opencode/opencode.jsonc` (`$OPENCODE_CONFIG`): opencode reads it but **cannot rewrite it**
- Outbound network access is restricted to what is configured in `config/opencode-sandbox-config.yaml`: domains whitelisted via Squid, plus direct `host-ports` / `intranet-endpoints`. Squid is started **only** when `http-domain-whitelist` is non-empty; otherwise egress is firewall-only (the iptables default-deny still applies)
- Host environment variables are forwarded as configured in the `env-passthrough` section — e.g. `GH_TOKEN` (as an API credential usable with `curl`; there is no `gh` CLI in the container)
- **No docker/podman inside the container**: no socket is mounted and no container runtime CLI is installed (there was no `docker-in-docker` option — it was fully removed). The container is also on a dedicated per-sandbox Docker network, so it cannot reach other host containers either
- `ocs rebuild` and `ocs start` cannot be run here (they manage the sandbox container itself from the host) — ask the user to run them on the host
- `gh` and `glab` CLIs are **not installed** (deliberately dropped) — do not expect them; use the API via `curl` with forwarded tokens. **Never** attempt `git push` or `git fetch`
- SSH is not available inside the container — `git push` and `git fetch` will fail; do not modify `git remote` URLs
- `shellcheck` is available for linting (installed via `apt`: bookworm 0.9.0)

## Lint (only CI-equivalent check)

```sh
shellcheck ocs bin/* bin/shared docker/entrypoint.sh
```

No tests, no formatter, no typecheck, no CI workflows.

### Manual smoke-test routine

After changing `config/Dockerfile.<profile>`, `docker/entrypoint.sh`, or `bin/*` (run from the host):

1. `ocs rebuild` — must print the extraction counts and build cleanly
2. `ocs start <name>` — container must come up and OpenCode must answer on `http://127.0.0.1:<port>`
3. `ocs test <name>` — automated security suite (builds/uses the **reserved** `Dockerfile.test` profile under its own `-test` image tag; starts its own one-shot test container; no web session needed): deterministic assertions (unprivileged user, no sensitive files, no docker escape channel, network isolation) plus an AI-agent red-team that must report all escapes blocked. Any FAIL is a regression — ocs test then removes the test image. A SKIP in the agent case usually means the model endpoint is not in `intranet-endpoints`
4. `ocs clean <name>` (one project) or `ocs kill` (all projects) — or just `docker rm` the test/web containers; `ocs clean` is the nuclear per-project option (also wipes the image and the in-project `.sandbox/` trees)

> **Self-hosted repo:** for this repository's own sandbox (which has its own `config/opencode-sandbox-config.yaml`), the `ocs` project-name argument can be **omitted** when the current directory is inside the project — `ocs` then resolves the project from the current directory (e.g. `ocs rebuild`, `ocs test` from the repo root).

## Conventions

- **Single entry point:** the root script `ocs` is the user-facing command and dispatches to `bin/ocs-*` (see its `case` list). New subcommands = add a `case` arm in `ocs` + a `bin/ocs-*` implementation (or reuse an existing one). Keep user-facing messages referring to `ocs <subcommand>`, not `bin/ocs-*` paths. **Current surface (keep in sync with `ocs help`):** `init <name> [-y] [-p|--dockerfile <p>] [--no-build]`, `rebuild`, `start`, `tui`, `run` (prompt **file or inline string**; first arg is the *name* only when it is a known project, otherwise the *prompt* and the project is resolved from CWD), `web`, `web-auth`, `terminal`, `test`, `list`, `clean` (alias `clear`), `kill`
- All `bin/` scripts: `set -euo pipefail` + `source bin/shared` (i.e. `source "${SCRIPT_DIR}/shared"`)
- After sourcing `shared`, re-assign `SCRIPT_DIR` if the script references other `bin/` scripts by path — `shared` overwrites `SCRIPT_DIR` with its own location (`bin/`)
- `bin/shared` provides: `find_sandbox_root` (walks up to `config/opencode-sandbox-config.yaml`), `use_sandbox_root`, `open_url`, `refresh_root_paths`, `valid_sandbox_name` (single source of the name rule — use it from every door), `valid_sandbox_cidr` / `derive_sandbox_subnet` / `ensure_sandbox_network`; it sets `SANDBOX_HOME` to the repo root (its parent) — keep that invariant
- New sandbox projects are created under `./sandboxes/<name>/` (repo-local; override: `$OPENCODE_SANDBOX_BASE`; constant `SANDBOXES_BASE` in `bin/shared`) via `ocs init <name>`. `./sandboxes/` is gitignored by default — new projects are not committed to the repo unless you `git add` them
- **Addressing:** `ocs <command> <project> [args]` — the dispatcher resolves the project dir from the name (or, without a name, from the current directory) and `cd`s into it before invoking the `bin/ocs-*` implementation. New subcommands = add a `case` arm in `ocs` (project-scoped ones go in the `resolve_project` branch) + a `bin/ocs-*` implementation. Keep user-facing messages referring to `ocs <command>`, not `bin/ocs-*` paths
- **Naming scheme:** `SANDBOX_ID` = `sandbox-name` + short hash of the project root path (computed in `bin/shared`). Every Docker object for a project is named with the short shared prefix **`ocs-`** + the ID: container `ocs-<SANDBOX_ID>` (one-shot runs append `-tui-$$` / `-run-$$` / `-test-$$`; the `ocs test` helper containers append `-peer-$$` / `-lst-ep-$$` / `-lst-host-$$`; `ocs terminal` attaches to the running web container and does not create its own), image `ocs-<SANDBOX_ID>`, test image `ocs-<SANDBOX_ID>-test`, network `ocs-net-<SANDBOX_ID>`. The prefix is short so users can `docker ps | grep '^ocs-'`. The legacy `opencode-sandbox-<SANDBOX_ID>` / `opencode-sandbox-net-<SANDBOX_ID>` scheme from before the rename is still matched (and cleaned) by `ocs clean` and `ocs kill`
- The entrypoint execs whatever `OPCODE_CMD` says as `dev` (if set), otherwise falls back to `opencode web --mdns --port ${OPENCODE_PORT}`. All container front doors (ocs start, ocs tui, ocs run, ocs test) go through the same entrypoint → squid+firewall always come first
- **No long-running container**: every door is a one-shot `docker run`. The only persistent artifact is the **image** (plus the per-sandbox Docker network). Nothing in `bin/` assumes a running sandbox except while that door is alive
- **Capabilities — least privilege**: every `docker run` uses `--cap-drop=ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID`, assembled by `compute_cap_flags()` in `bin/shared` (the single source). `NET_ADMIN` is required for the container-internal iptables firewall; `SETUID`+`SETGID` are required for the `gosu dev` root→dev drop that **every** door performs (and for squid's root→proxy drop when squid runs) — they cannot be trimmed without `gosu dev` failing with "operation not permitted". Everything else (mknod, dac_override, chown, kill, …) is dropped so the bounding set is exactly `{NET_ADMIN, SETUID, SETGID}` (CapBnd `00000000000010c0`). Any new door must reuse `build_run_flags` so it gets these
- **Resource limits — host-DoS guard**: every `docker run` (all doors, including `ocs test`) also gets `--memory=4g --memory-swap=4g --cpus=2.0 --pids-limit=256 --security-opt=no-new-privileges:true`, appended unconditionally in `build_run_flags` (the single source). Values are fixed defaults; raise them there if a project needs more (run flags are assembled at start time, no rebuild needed). Test case 10 verifies all four limits via the container's cgroups/`/proc/self/status`; test case 11 proves live two-container isolation (a peer container on a scratch `ocs-scratch-*` network must be name-unresolvable and TCP-unreachable from the test container — `ocs test` starts/stops/`rm`s that peer itself)
- **Agent DNS — tunnel gate (uid-scoped, nat-table):** Docker's built-in resolver `127.0.0.11:53` is a forwarder to the internet and is a working DNS-exfil/C2 channel if left open to the agent. The gate is implemented in `docker/entrypoint.sh` and is **UID-scoped** so that squid (proxy uid) keeps its resolver for whitelisted domains.
     **IMPORTANT MECHANISM — do not regress to filter-table-only.** As of 2026-09-21 we empirically confirmed (moby/moby#40515 matches) that the `127.0.0.11:53` socket-owner path does **not** match a filter-table `-m owner --uid-owner $DEV_UID` rule: the counter stays at `pkts=0` for the dev rule, the `-o lo ACCEPT` rule catches it, and a probe from `dev` succeeds. The nat-table **does** match — `-m owner` there uses the *sending* socket's uid. The entrypoint therefore installs two layers:
     1. **Primary (works)** — nat-table, inserted at the front before Docker's `DOCKER_OUTPUT` DNAT:
     ```
     iptables -t nat -I OUTPUT 1 -d 127.0.0.11 -p udp --dport 53 -m owner --uid-owner $DEV_UID -j DNAT --to-destination 127.0.0.1:1
     iptables -t nat -I OUTPUT 2 -d 127.0.0.11 -p tcp --dport 53 -m owner --uid-owner $DEV_UID -j DNAT --to-destination 127.0.0.1:1
     ```
     (`DROP` in the nat table is refused by iptables v1.8.9's nftables backend; DNAT-to-dead is the functional equivalent. `127.0.0.1:1` is a loopback dead socket — no listener, no response, timeout visible to the sender.)
     2. **Defence-in-depth (harmless if the nat rule already catches, also covers IPv6)** — filter-table drops in the old style (`-p udp/tcp --dport 53` for both `iptables` and `ip6tables`) scoped to the dev uid.
     The gate is controlled by a top-level scalar `agent-dns: deny|allow` in `opencode-sandbox-config.yaml` (default `deny`, made explicit in `config/opencode-sandbox-config.yaml:21`). `bin/ocs-rebuild-container` validates the value, `rm -f` the prior artifact (the build dir may hold a stale 0400 file whose owner has no write bit — `rm` first), writes `agent-dns` as `0600` (owner rw, so the next rebuild can overwrite), and every `config/Dockerfile.*` `COPY`s it to `/etc/agent-dns`. The entrypoint reads it at start. `allow` re-opens the tunnel **explicitly by config choice** — only when an endpoint is a hostname (e.g. a model `baseURL` that is not an IP). `ocs test` case 12 verifies: `deny` → `dev`'s `dig A example.com @127.0.0.11` (and the TXT-exfil pattern) returns nothing; plus a positive squid check when the whitelist is non-empty. Changing `agent-dns` requires **a rebuild** (the value is baked in). **Verify with `ocs rebuild <project>` then `ocs test <project>` (or by starting a container and running `dig` as `dev`) — the nat rule must be present in `iptables -t nat -S OUTPUT` at position 1 and 2.**
- **`/opencode-password` is `root:root 0600`** (enforced in every `config/Dockerfile.*`): the entrypoint (root) is the sole reader — it seeds `OPENCODE_SERVER_PASSWORD`, which `gosu` passes to dev as env. Dev never reads the file. Keeping it root-owned means the container does not need the `DAC_OVERRIDE` cap
- **In-container mounts (the full map, all set by `build_run_flags`):** (1) the **workspace** (`workspace:` key, default `workspace/`) → `/workspace` (rw — the single user rw dir); (2) the opencode **state** tree (`.sandbox/state/opencode/`, persistent) → `/home/dev/.local/share/opencode` (rw — a neutral path; this is opencode's own session data, reusable across runs); (3) `config/opencode.jsonc` → `/etc/opencode/opencode.jsonc` (ro, via `$OPENCODE_CONFIG`; the agent reads it but cannot rewrite it). For the self-hosted repo (`workspace: .`) the runtime tree `.sandbox/` sits inside the mounted workspace, so `build_run_flags` masks it with an empty read-only dir at `/workspace/.sandbox` so it is never visible. `.git`, `config/` (yaml), and the rest of the host tree are **not** mounted. Override the base with `$OPENCODE_SANDBOX_RUNTIME_BASE` / `$OPENCODE_SANDBOX_BUILD_BASE` / `$OPENCODE_SANDBOX_STATE_BASE`
- The shared model constant is `OPENCODE_MODEL` in `bin/shared` (keep in sync with `model` in `config/opencode.jsonc`). Every CLI invocation pins it with `-m`; opencode.jsonc additionally locks `enabled_providers: ["ollama"]` and denies `webfetch` / `websearch`
- `build_run_flags` (in `bin/shared`) is the single place that assembles env passthrough / static env / extra mounts / add-host / `--network` for `docker run`; new `bin/ocs-*` container commands must reuse it — that is what gives every run the dedicated sandbox network
- Config templates (copied into target projects by `ocs init`) live in `config/` — **the single source**: the repo's own `config/` and the template are the same files. `config/` also holds the Docker image **profiles** `Dockerfile.<name>` (see below)
- **Image profiles:** `config/Dockerfile.minimal` (harness + python3, the default), `config/Dockerfile.full` (full dev toolchain), and the reserved `config/Dockerfile.test` (network-analysis suite for `ocs test`). A project picks one via the `dockerfile:` config key (default `minimal`); `ocs rebuild` builds `config/Dockerfile.$(dockerfile)` under `ocs-<SANDBOX_ID>`. `ocs test` builds the *reserved* `test` profile under a separate tag `ocs-<SANDBOX_ID>-test` (via `OPENCODE_DOCKERFILE_OVERRIDE=test`) so it never clobbers the working image; that test image is cached on a pass (fast re-run) and removed on a fail/crash (`ocs kill` removes it too). `ocs init` lists the `Dockerfile.*` files (excluding `test`) and prompts for a profile, writing `dockerfile:` into the new project config. **Test-only build args (the harness):** `Dockerfile.test` declares `HARNESS_EP_IP` / `HARNESS_EP_PORT` (8765) / `HARNESS_HOST_PORT` (8766) and bakes them into its allow-lists (`/etc/intranet-endpoints.txt`, `/etc/host-ports.txt`) + creates `/mnt/ocs-fwd` + copies `test/listener.py` to `/opt/ocs-test/listener.py`. `bin/ocs-rebuild-container` accepts an optional `EXTRA_BUILD_ARGS` env (space-separated docker-build flags) that `ocs test` uses to inject the derived harness IP (`<subnet>.50`) and the labels `ocs-harness-ep` / `ocs-test-api`. The cached test image is reused only while both labels still match (`TEST_API` in `bin/ocs-test` is a manually-bumped version — increase it whenever the harness mechanism changes, so stale cached test images get rebuilt). The `minimal`/`full` profiles never set these args: the harness rules can only ever exist in the short-lived `-test` image.
- Container-runtime files (`docker/entrypoint.sh`, `docker/squid.conf`) live under `docker/` — they are copied flat into the build context by `ocs rebuild`, so their `COPY`-relative layout in the Dockerfile profiles stays unchanged
- Security test suite: `test/common.sh` (helpers) + `test/cases/*.sh` run **inside** a one-shot container started by `ocs test` (it does not need a running web session). Add new cases as `test/cases/<NN>-<name>.sh` (NN in zero-padded order), exit 0 = PASS / 1 = FAIL / 0 with a leading `SKIP:` line = skipped. Keep each case self-contained; the AI-agent case (08) drives `opencode run` non-interactively, writes its JSON report to `/tmp` (not the workspace), judged by case 09
- Cleanup: `ocs kill` removes all sandbox containers, images, and networks (all three `ocs-*` name families) across all projects — safe after crashes/aborts; optional name filter as first argument. `ocs clean <name>` is the **nuclear per-project** variant: removes exactly one project's containers (running + stopped), **both images** (working + `-test`), dedicated network, **and** both on-disk trees (`.sandbox/build/`, `.sandbox/state/`), never touching the project's source files or any other project. Use `clean` to discard one sandbox's runtime; use `kill` to reset the whole host's sandbox set
## Design decisions

### Image profiles (Dockerfile.minimal / .full / .test)

The image base is `python:3.13-slim-bookworm` (Debian 12) for **every** profile. **All OS packages** are installed via `apt` (no `mise`/Nix toolchain layer). Python libraries ship two ways, depending on profile: `apt` (the base `python3`) and `pip` (the `full` profile adds the dev data/office/sci stack). There is no separate package-manager layer.

Profiles (each a self-contained `config/Dockerfile.<name>`, all sharing the same `docker/entrypoint.sh` + `docker/squid.conf` + harness):
- **`Dockerfile.minimal`** (the default) — harness only: `squid iptables gosu iproute2 xdg-utils git curl procps` + `python3` (base, no pip) + the opencode CLI + headless `xdg-open` stub. Smallest attack surface; fits most agent work that just needs shell + python + network.
- **`Dockerfile.full`** — everything `minimal` has **plus** the dev toolchain: build tools, `shellcheck`, and a large `pip` install (pandas/numpy/scipy/matplotlib + office/PDF/OCR/image/HTML/email/sci/ML libs) plus `tesseract-ocr`, ghostscript, mupdf, graphviz, the font stack, and `freetds` (for `pymssql`). `yearfrac` is pinned to `0.4.8` (its sdist build is broken at the latest release).
- **`Dockerfile.test`** (reserved, **not selectable**) — harness + `python3` + `jq` + the full network-analysis suite (`nmap tcpdump net-tools iproute2 iputils-ping netcat-openbsd dnsutils whois traceroute mtr-tiny`). Used **only** by `ocs test`, which builds it under the separate tag `ocs-<SANDBOX_ID>-test` and always removes it on exit. A project can never set `dockerfile: test`.

OpenCode is **not** in Debian, so it comes from the official installer (`https://opencode.ai/install | bash -s -- --no-modify-path`) and is copied to `/usr/local/bin/opencode` in every profile.

`gh` and `glab` CLIs are deliberately **not** installed. GitHub/GitLab access must go through the REST API (`curl`) using tokens forwarded from the host.

### No container runtime inside the sandbox (docker-in-docker removed)

An earlier version of the sandbox supported `docker-in-docker: true`, which installed `docker.io` into the image and mounted the host Docker socket, letting the agent build/run host containers. **That capability was fully removed** (Dockerfile, entrypoint, rebuild config key, tests 06/08/09) because a mounted host socket is the single most powerful escape vector. Test case 06 now *hard-fails* if a socket, `docker` CLI, or `podman` CLI is present in the image. Do not reintroduce any of them as a "feature".

### Per-sandbox dedicated Docker network (configured IP range)

Every `docker run` (web / TUI / one-shot / test) attaches to a **named, persistent** network `ocs-net-<SANDBOX_ID>` created on demand by `ensure_sandbox_network()` in `bin/shared` (via `build_run_flags`).

IP range: the config key **`sandbox-network-cidr`** (top-level scalar; default `10.77.0.0/16`) defines the shared range for **all** sandboxes on this host. `ocs rebuild` writes it to the state dir (`sandbox-network-cidr.txt`); `derive_sandbox_subnet()` (in `bin/shared`) then assigns this sandbox a **deterministic /24 inside that range** (hash of `SANDBOX_ID`, persisted in `sandbox-network-map` so it survives rebuilds). If the configured range changes, existing networks are recreated with the new subnet.

Effects:
- All sandbox containers live inside the configured private range (e.g. `10.77.x.x`)
- Two different projects can never share an L2 segment → no cross-container reachability in either direction
- Sandbox containers are invisible to — and cannot probe — other Docker containers on the host (which stay on the default bridge or their own networks, completely unaffected)
- All *container* artifacts of one sandbox share the same `SANDBOX_ID`-derived names (container/image/network) — one fixed identity per project, used by every door

Note: parallel runs of the **same** sandbox (web + TUI) also share the opencode state dir — that is a known concurrency limitation (opencode's sqlite may lock), not an isolation one.

The network is persistent by design; `ocs clean <name>` / `ocs kill` remove it. The container-internal firewall (Squid + default-deny OUTPUT) still bounds every other outbound direction.

### `intranet-endpoints` — direct IPv4:port firewall allowlist

`opencode-sandbox-config.yaml` accepts an `intranet-endpoints:` list of `ipv4:port` entries (one per line, no ranges, no CIDR). This is a generalisation of `host-ports` for on-prem services not running on the host.

- `ocs rebuild` extracts these into `intranet-endpoints.txt` and validates the shape — `ipv4:port`, octets 0–255, port 1–65535 — so a malformed entry fails the rebuild with a clear error instead of aborting the container at start (iptables rejects bad IPs/ports).
- The Dockerfile profiles (`config/Dockerfile.*`) each copy it to `/etc/intranet-endpoints.txt`.
- `docker/entrypoint.sh` adds one `iptables -A OUTPUT -d <ip> -p tcp --dport <port> -j ACCEPT` per entry (so the connection bypasses Squid) **and** appends each IP to `no_proxy`/`NO_PROXY` so clients don't route it through the proxy.

A rebuild is required after changing this section.

### `opencode-sandbox-config.yaml` — YAML subset parsed in bash

The config file uses a YAML subset deliberately chosen to be parseable without any external dependencies. No `yq`, `python`, or other tools are required on the host.

The supported subset is intentionally narrow:
- Top-level scalar values: `key: value` (no leading whitespace, has a value)
- Top-level section headers: `key:` (no leading whitespace, no value)
- List items one level deep: `  - value`
- Map entries one level deep: `  key: value`
- Line comments (`#`) and blank lines
- Inline comments are stripped **everywhere a value is read** — in scalars, list items, and map values (`  - 5432 # postgres` → `5432`; `  TOKEN: HOST_TOKEN # note` → `TOKEN=HOST_TOKEN`). Comment-only items (`  - # note`) are skipped. Do not rely on a `#` in a value surviving to the artifact files; they never do

The parser distinguishes scalars from section headers by whether a value is present after the colon. A top-level scalar clears the current section context; entries that follow it are not attributed to any section until the next section header appears.

To add a new top-level scalar: declare a `cfg_<name>` variable before the parse loop, add a `case` arm inside the loop, and add the corresponding behaviour in the "Post-parse: apply scalar flags" block after the loop.

Anything outside this subset — anchors, multi-line strings, nested structures, typed values — is silently ignored by the parser in `ocs rebuild`. Do not add configuration that relies on YAML features beyond the above. If richer configuration is ever needed, switch to a proper YAML parser (`yq`) rather than extending the bash parser.

### bash 3.2 compatibility (macOS)

macOS ships bash 3.2 as the system shell. All scripts must be compatible with it:
- Non-greedy regex quantifiers (`*?`, `+?`) are **not supported** — use character classes instead (e.g. `[^:]+` rather than `.*?[^:]`)
- Test regex changes on both Linux (bash 5) and macOS (bash 3.2) before committing
