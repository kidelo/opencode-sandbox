# Authors

opencode-sandbox is a **fork** of the upstream [comsysto/opencode-sandbox](https://github.com/comsysto/opencode-sandbox) project (Apache-2.0). Attribution follows the Apache-2.0 terms: the upstream authorship is preserved, and this fork's additional work is listed below.

## Upstream — comsysto

The original project.

- **Comsysto Reply GmbH** — original project and lead maintainer of the upstream `opencode-sandbox`

## This fork — kidelo

Fork maintenance, hardening, and the changes listed in ["Changes versus upstream"](README.md#changes-versus-upstream) (single `ocs` dispatcher, per-sandbox Docker networks, one-shot container lifecycle, image profiles, `ocs clean` / `ocs kill --purge`/`--state`, the `ocs test` security suite, and the `workspace` / read-only-config / hidden-`.sandbox` mount model).

- **kidelo** (`github.com/kidelo`) — fork maintainer

### AI assistance

New and changed code in this fork was developed with AI assistance (**Qwen 3.8**, accessed through a local Ollama-compatible endpoint). Contributions remain licensed under the Apache-2.0 terms of the LICENSE file.

## Licensing

The [LICENSE](LICENSE) file (Apache License 2.0) governs the whole repository and applies to both the upstream-derived and fork-authored portions. Copyrights of all parties above are asserted and preserved in accordance with the Apache-2.0 requirements.

## Want to contribute?

Open a pull request against `github.com/kidelo/opencode-sandbox`. Contributions add you to this list and are licensed under the same Apache-2.0 terms. See [CONTRIBUTING guidelines](AGENTS.md) for the project's conventions.
