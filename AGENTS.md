# Repository instructions

## Mission

Maintain a secure, reproducible Ubuntu 26.04 LTS x86_64 development environment,
for WSL2 or plain Linux, for an expert software engineer specialising in security
and AI. It is the Linux half of a workstation whose macOS half is the operator's
`setup-dev-mac` repository, from which this one is ported in spirit.

This repository is infrastructure code. Treat changes as security-sensitive,
operationally consequential and expected to remain understandable years later.

## Current user decisions

These are deliberate defaults, not placeholders:

- Target platform: Ubuntu 26.04 LTS, x86_64 ONLY. `--target wsl` is Ubuntu in WSL2
  with systemd on; `--target linux` is bare metal or a VM, headless. Any other
  distro, release or architecture fails closed before anything changes. Detect WSL;
  never assume it. There are no arm64 branches (ADR-002).
- Release fallback: if a vendor repo needed by a default or `gpu-nvidia` profile
  publishes no 26.04 packages, the whole repo targets 24.04 for v1. Repos from
  different Ubuntu releases are never mixed (ADR-002).
- Never write a capability claim that is true of only one target. Detect it rather
  than remember it, and report accordingly.
- Package layers (ADR-003): apt for the base and for vendor repos, Homebrew on Linux
  for CLI tools, mise for language runtimes, uv for Python.
- Homebrew is installed by `git clone` at a pinned tag and commit, with no install
  script (ADR-004).
- Configuration engine: chezmoi (`.chezmoiroot` points at `chezmoi/`).
- Commit signing is SSH, with a per-machine `~/.ssh/id_ed25519` that is never
  copied. The work identity splits through `includeIf gitdir:`. `core.autocrlf` is
  false (ADR-005).
- Default interactive shell: zsh. fish is the mutually exclusive alternative. The
  login shell is reported, never changed (ADR-007).
- Default package profiles: core, dev, security, kubernetes, backup. Optional:
  productivity-extra.
- Stateful services belong to the project that owns them, in containers. The
  repository owns only stateless substrate.
- Every container port the repository publishes binds `127.0.0.1`.
- Exploit development, malware analysis and untrusted binaries belong in an
  isolated VM, not in this environment.

## Non-negotiable architecture

Use the smallest appropriate execution boundary:

1. **Linux host (WSL distro or machine)** for CLI tools and low-latency work.
2. **Project-local uv environment** for Python and AI workloads.
3. **Containers** for databases, vector stores, queues and batch scanners.
4. **Isolated VM** for hostile or kernel-sensitive work.

Do not containerise a tool merely for consistency when doing so removes a required
host capability. Do not install a daemon natively merely because a package exists.

## Sources of truth

- `profiles/*.Brewfile`: Homebrew-on-Linux profiles (formulae only).
- `apt/`: base package lists, vendor repo `.sources`, committed keys and
  `pins.lock`.
- `chezmoi/`: user configuration and idempotent apply hooks.
- `mcp/`: the approved MCP policy catalogue.
- `script/`: orchestration, validation and maintenance commands.
- `docs/ARCHITECTURE.md`: current boundaries and configuration flow.
- `docs/DECISIONS.md`: durable architectural decisions (ADR log).
- `docs/OPERATIONS.md`: installation, update, verification and recovery runbook.
- `TASKS.md`: unfinished work only.

## Change workflow

Before editing:

1. Read `README.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`.
2. Inspect the relevant source-of-truth files before proposing changes.
3. Check `git status`; do not overwrite unrelated user work.
4. Verify package names, licences and product behaviour against primary vendor
   documentation when network access is available. State when verification was
   impossible.

While editing:

- Prefer a small focused patch over a broad rewrite.
- Preserve idempotency.
- Keep implementation logic in small scripts; keep `justfile` recipes as thin
  command aliases.
- Explain each package's purpose and why its execution boundary is correct.
- Keep mutually exclusive alternatives in separate profile fragments.
- One tool per job in the default profile, capped at 70 entries (ADR-008).
- Never put credentials, recovery keys, private addresses or machine-specific
  absolute paths in tracked files.
- Never run the bootstrap as root; use `sudo` per command.
- No download-and-run scripts, including in CI. The Homebrew bootstrap is a pinned
  clone, not an installer.
- Every GitHub Action is pinned to a 40-hex commit SHA and every CI tool to an
  exact version.
- The repository never commits, tags, pushes, changes the login shell (`chsh`) or
  edits `/etc/shells`.

After editing:

1. Run `./script/test` for every change, including documentation changes that
   affect instructions or workflows.
2. Run the most specific checks for the changed area.
3. Report what was tested and what could not be tested.
4. Do not commit, amend, tag, push or create a branch unless the operator asks.

## Standard commands

```bash
./bootstrap plan
./bootstrap apply
./script/test
REQUIRE_LINTERS=1 REQUIRE_CHEZMOI=1 ./script/test   # what CI runs; no silent skips
```

## Testing expectations

`./script/test` runs every test under `tests/` listed in its `TESTS` array. It
requires bash 5 and refuses to run under anything older.

- Shell scripts are discovered by shebang via `script/shell-files`, never by
  filename extension. Do not introduce a separate file selector in tests or CI.
- Tests skip a missing linter with a message unless `REQUIRE_LINTERS=1`, when they
  fail instead. Run with that variable set before believing a green result.
- `REQUIRE_LINTERS=1 REQUIRE_CHEZMOI=1 ./script/test` must fail rather than skip
  when a tool is missing.

## Shell standards

- Bash scripts use `#!/usr/bin/env bash` and `set -Eeuo pipefail`.
- Bash 5 or newer is required and asserted with `require_bash5`. The macOS repo's
  bash 3.2 compatibility checks are deliberately not ported.
- Quote variable expansions unless deliberate word splitting is documented.
- Prefer arrays for command construction.
- Avoid `eval` except for vendor-generated shell initialisation such as
  `brew shellenv`, and explain its use in a comment.
- Use `mktemp` plus traps for temporary state.
- Back up user-owned files before replacement.
- Fail closed on invalid choices and ambiguous security state.

## Security invariants

Do not weaken these without explicit operator approval and a documented decision:

- Container ports bind to `127.0.0.1` by default.
- No general-purpose container mounts `/var/run/docker.sock`.
- No container receives the whole home directory, the SSH directory or all cloud
  credentials.
- MCP servers are allowlisted by command or URL, never by name, and every package
  spec carries an explicit version.
- No tool reports usage to its vendor where a verified opt-out exists (ADR-006).
  The shells carry exactly `HOMEBREW_NO_ANALYTICS=1`,
  `AZURE_CORE_COLLECT_TELEMETRY=false`, `CHECKPOINT_DISABLE=1` and
  `DO_NOT_TRACK=1`, identical in zsh and fish.
- Interactive shells, host firewalls and password managers remain mutually
  exclusive choices.
- Fail closed on ambiguous security state.

## Documentation contract

Update documentation in the same patch when behaviour, defaults, commands, package
placement or security assumptions change. `README.md` is the concise entry point,
`docs/ARCHITECTURE.md` the current-state design, `docs/DECISIONS.md` the durable
rationale, `docs/OPERATIONS.md` the runbook and `TASKS.md` unfinished work only.
