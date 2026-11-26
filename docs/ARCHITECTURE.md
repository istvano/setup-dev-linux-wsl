# Architecture

Current state of the design. Rationale lives in `DECISIONS.md`.

## Targets

Ubuntu 26.04 LTS on x86_64, either in WSL2 (`--target wsl`) or on a headless
machine or VM (`--target linux`). Nothing else is supported.

## Layers

1. apt: a small base set (`apt/base.list`). Signed vendor repos (committed keys,
   `apt/vendor.list`, deb822 sources) are applied per profile and target by
   `script/apt-vendor`.
2. Homebrew on Linux: CLI tools, from rendered profile Brewfiles.
3. mise: language runtimes at the latest stable version (node LTS, Java LTS lines; ADR-011); uv for Python.
4. chezmoi: dotfiles, rooted at `chezmoi/` through `.chezmoiroot`.

## Flow

`./bootstrap plan|apply` runs the guards (bash 5, not root, x86_64, Ubuntu 26.04,
target, profiles including `core`) before any step, then `script/apt-base`,
`script/apt-vendor`, `script/install-homebrew`, `script/packages`, chezmoi and `script/verify`. On a first
run chezmoi is run as `chezmoi init --source <repo>/chezmoi` with
`--promptMultichoice`, `--promptChoice` and `--promptString` (keyed by prompt text)
so its data matches what packages installed. Once `~/.config/chezmoi/chezmoi.toml`
exists its `[data]` is the record: options default from it, a disagreeing option is
refused before any step, and `chezmoi init` is given no recorded value at all
(`prompt*Once` returns the record, and a value such as `Doe, Jane` cannot survive
the comma-separated flag syntax). Then the changing targets are backed up, then
`chezmoi apply`. `plan` uses only the `--check` forms and never runs `chezmoi init`.

`script/verify` and `script/identity` read the same record. The identity check
follows `gitSigningMethod`: `ssh` signs and verifies a commit, `gpg` asserts
`gpg.format = openpgp` without exercising signing, `none` needs only the SSH key.
The runtimes hook (`run_onchange_after_20`) fails when `mise install` fails, so
chezmoi retries it on the next apply.
The uv-tools hook (`run_onchange_after_29`, aider) and the telemetry hook
(`run_after_31`, Go and aider opt-outs; every apply, so it retries) never fail the
apply (ADR-015).

## Profiles

Default: core, dev, security, kubernetes, backup. Opt-in: productivity-extra,
security-scan, cloud, cloud-aws, cloud-azure, docs (ADR-010). Each is a
`profiles/<name>.Brewfile` fragment of formulae only. `gcloud` and `azure-cli` are
macOS-only casks in homebrew-core, so they wait for the vendor-apt milestone. Tools and
approaches that were considered and refused are recorded in [DROPPED.md](DROPPED.md).

## Execution boundaries

Linux host for CLI tools, project-local uv environments for Python and AI work,
containers for stateful services and scanners, an isolated VM for hostile work.

## Test harness

`script/test` requires bash 5 and runs the tests in `tests/`. Shell scripts are
found by shebang through `script/shell-files`, so every check lints the same set.
