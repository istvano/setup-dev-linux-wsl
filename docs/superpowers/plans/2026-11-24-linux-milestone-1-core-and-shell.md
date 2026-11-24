# setup-dev-linux-wsl Milestone 1 (L0–L2): skeleton, core tools, Mac shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fresh Ubuntu 26.04 x86_64 machine or WSL distro runs `./bootstrap apply` and ends with apt base packages, Homebrew-on-Linux with the core/dev/security/kubernetes/backup Brewfiles, mise runtimes, uv, and the Mac's shell, git and SSH configuration ported, with SSH commit signing working, all proven in x86_64 GitHub Actions.

**Architecture:** A bash repo mirroring `setup-dev-mac`: `bootstrap` orchestrates small scripts in `script/`, shared helpers in `script/lib/`, package declarations in `apt/` and `profiles/*.Brewfile`, user config in a chezmoi source under `chezmoi/` (`.chezmoiroot`), and grep/exec-based tests under `tests/` run by `script/test`. Docker, GPU, agents and WSL integration are later milestones.

**Tech Stack:** bash 5.2 (Ubuntu), apt, Homebrew on Linux, mise, uv, chezmoi, shellcheck, shfmt, actionlint, gitleaks, yamllint, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-24-setup-dev-win-linux-design.md` (§2, §5, §7.1–7.5, §7.10, §8.4–8.5). Reference implementation to port from: `~/workspace/setup-dev-mac` (read-only).

## Global Constraints

- Targets: Ubuntu **26.04** LTS, **x86_64** only; `--target wsl` or `--target linux`. Fail closed on anything else, before any change.
- If a vendor repo needed by a default or `gpu-nvidia` profile lacks 26.04 packages, the whole repo targets 24.04 for v1; never mix release repos. (Checked in Task 5.)
- Bash scripts: `#!/usr/bin/env bash`, `set -Eeuo pipefail`, quoted expansions, arrays for commands, `mktemp` + traps, no `eval` except vendor shell init (`brew shellenv`), with a comment. Bash ≥ 5 is required and asserted (`require_bash5`); the Mac's bash 3.2 checks are **not** ported.
- Never run as root; use `sudo` per command.
- No download-and-run scripts. Homebrew is installed by `git clone` at a pinned tag + commit (Task 6). No `curl … | sh` anywhere, including CI.
- Every GitHub Action pinned to a 40-hex commit SHA; every CI tool pinned to an exact version.
- No tool reports usage to its vendor where a verified opt-out exists. The shells carry exactly: `HOMEBREW_NO_ANALYTICS=1`, `AZURE_CORE_COLLECT_TELEMETRY=false`, `CHECKPOINT_DISABLE=1`, `DO_NOT_TRACK=1`, identical in zsh and fish.
- No credentials, private addresses or machine-specific absolute paths in tracked files.
- Git signing default: **ssh**, per-machine `~/.ssh/id_ed25519`, never copied. Work identity split via `includeIf gitdir:` carried over. `core.autocrlf=false`.
- `.gitattributes`: `* text=auto eol=lf`.
- The repo never commits, tags, pushes, changes the login shell (`chsh`) or edits `/etc/shells`.
- `REQUIRE_LINTERS=1 REQUIRE_CHEZMOI=1 ./script/test` must fail rather than skip when a tool is missing.

## Review Focus

1. **Re-running `./bootstrap apply` on a provisioned machine** — must be a no-op: no duplicate apt entries, Homebrew not re-cloned, existing `~/.ssh/id_ed25519` untouched, chezmoi not re-prompting. (Test: Task 12 integration job runs apply twice and asserts the second run changes nothing.)
2. **Run as root or under `sudo ./bootstrap`** — refuse with a message before any change. (Test: Task 3 `require_not_root` + Task 12 `bootstrap` refusal.)
3. **Wrong OS, release or arch** (Ubuntu 24.04, Debian, aarch64) — refuse before any change. (Test: Task 3 fixtures.)
4. **Existing dotfiles from Ubuntu's skel** (`~/.bashrc`, `~/.profile`, a pre-existing `~/.zshrc` or `~/.gitconfig`) — managed targets are backed up before replacement, unmanaged files untouched. (Test: Task 12 integration job seeds a `~/.gitconfig` and asserts a backup exists after apply.)
5. **Interrupted Homebrew clone** (partial `/home/linuxbrew/.linuxbrew/Homebrew`) — a re-run must detect a tree whose HEAD isn't the locked commit and stop with instructions, never proceed on it. (Test: Task 6.)

---

## File structure

```
bootstrap                                   entrypoint: plan | apply
script/test                                 runs tests/*.sh in order
script/shell-files                          shebang-based selector (ported)
script/lib/common.sh                        logging, die, require_*, atomic_write, backup_file, platform detection
script/lib/profiles.sh                      DEFAULT_PROFILES, VALID_PROFILES, validate_profiles
script/render-brewfile                      profiles → one Brewfile
script/apt-base                             install/check apt/base.list
script/install-homebrew                     pinned git-clone install
script/packages                             render + brew bundle install/check
script/identity                             --check SSH key + signing
script/verify                               milestone-1 verification
apt/base.list                               apt packages, one per line, commented
homebrew/brew.lock                          tag + commit of Homebrew/brew
profiles/{core,dev,security,kubernetes,backup,productivity-extra,shell-zsh,shell-fish}.Brewfile
chezmoi/.chezmoi.toml.tmpl                  prompts + detected data
chezmoi/.chezmoiignore
chezmoi/.chezmoitemplates/brew-shellenv
chezmoi/dot_zshrc.tmpl, dot_config/fish/config.fish.tmpl, dot_config/starship.toml,
chezmoi/dot_config/atuin/config.toml, dot_config/ripgrep/ripgreprc, dot_tmux.conf,
chezmoi/dot_config/mise/config.toml.tmpl, dot_local/bin/executable_conn,
chezmoi/dot_gitconfig.tmpl, dot_config/git/config-work.tmpl, private_dot_ssh/config.tmpl,
chezmoi/run_onchange_after_12_ssh-key.sh.tmpl, run_onchange_after_13_allowed-signers.sh.tmpl,
chezmoi/run_onchange_after_20_configure-runtimes.sh.tmpl, run_onchange_after_30_report-login-shell.sh.tmpl
tests/lib.sh, shell-syntax.sh, format.sh, placement-policy.sh, platform.sh, profiles.sh,
tests/render-brewfile.sh, apt.sh, homebrew.sh, chezmoi-templates.sh, bootstrap.sh
tests/fixtures/os-release/*, tests/fixtures/chezmoi/{wsl,linux,full}.toml
.github/workflows/validate.yml              static job + integration job
README.md AGENTS.md CLAUDE.md TASKS.md docs/{ARCHITECTURE,DECISIONS,OPERATIONS}.md
.gitattributes .gitignore .chezmoiroot
```

---

### Task 1: Repository skeleton, docs seed and test harness

**Files:**
- Create: `README.md`, `AGENTS.md`, `CLAUDE.md`, `TASKS.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/OPERATIONS.md`, `.gitattributes`, `.gitignore`, `.chezmoiroot`
- Create: `script/lib/common.sh`, `script/shell-files`, `script/test`
- Create: `tests/lib.sh`, `tests/shell-syntax.sh`, `tests/format.sh`

**Interfaces:**
- Produces (`script/lib/common.sh`): `log MSG`, `success MSG`, `warn MSG`, `die MSG` (exit 1), `command_exists NAME`, `require_value FLAG VALUE`, `require_bash5`, `confirm PROMPT` (returns 0/1; non-interactive → 1), `backup_file PATH` (copies to `PATH.backup.<UTC-timestamp>`, prints the backup path), `atomic_write PATH` (stdin → temp in same dir → `mv`).
- Produces (`tests/lib.sh`): `assert_match PATTERN FILES...`, `refute_match PATTERN FILES...`, `refute_command DESCRIPTION CMD...` — ported verbatim from `setup-dev-mac/tests/lib.sh`.
- Produces (`script/shell-files`): prints every bash/sh script by shebang; `--zsh` prints zsh scripts; exits 1 if none found. Ported from the Mac, unchanged except the header comment.

- [ ] **Step 1: Write the docs seed.**
  `AGENTS.md` mirrors `setup-dev-mac/AGENTS.md` sections (Mission, Current user decisions, Non-negotiable architecture, Sources of truth, Change workflow, Standard commands, Testing expectations, Shell standards, Security invariants, Documentation contract), rewritten for Ubuntu with every Global Constraint above. `CLAUDE.md` contains the single line `@AGENTS.md`. `docs/DECISIONS.md` seeds these ADRs (status accepted, each 3–10 lines, citing the spec section): ADR-001 Two repos, this one Linux-only (§3); unrelated to the operator's existing `istvano/setup-dev-linux`, which is never modified or depended on; ADR-002 Ubuntu 26.04 x86_64 only, release fallback rule (§7.1); ADR-003 apt base + vendor apt + Homebrew CLI + mise runtimes (§3); ADR-004 Homebrew by pinned git clone, no install script (§7.3); ADR-005 SSH commit signing with per-machine keys, deliberately differing from setup-dev-mac ADR-017 (§7.5); ADR-006 Telemetry opt-outs carried from setup-dev-mac ADR-046 (§8.4); ADR-007 Login shell reported, never changed (§6.9); ADR-008 One tool per job, default-profile cap 70 (setup-dev-mac ADR-022). `README.md`: purpose, targets, `./bootstrap plan|apply` quick start, profile table, links. `TASKS.md`: milestones 2+ from spec §9 (L3–L6). `.gitattributes`: `* text=auto eol=lf`. `.chezmoiroot`: `chezmoi`.

- [ ] **Step 2: Write `tests/shell-syntax.sh`** — collects files from `script/shell-files`, runs `bash -n` on each, then `shellcheck -x` on all (skip with message unless `REQUIRE_LINTERS=1`, then fail), then `zsh -n` on each `script/shell-files --zsh` result (same skip/fail rule; tolerate zero zsh files until Task 10 by checking `--zsh` exit status explicitly).
  `tests/format.sh` — `shfmt -d -i 2 -ci` over the same files; `actionlint` if `.github/workflows` exists; `gitleaks detect --no-banner --redact`; each with the same `REQUIRE_LINTERS` rule.

- [ ] **Step 3: Write `script/test`** with `TESTS=(shell-syntax format)`, running each `bash tests/$t.sh`, then printing `All repository tests passed.` It calls `require_bash5` first.

- [ ] **Step 4: Run** `REQUIRE_LINTERS=1 ./script/test` in CI or a Linux container (bash 5). On the Mac, `./script/test` under `/bin/bash` 3.2 must be refused by `require_bash5` with `bash 5 or newer is required` — confirm that refusal; do not install a newer bash on the Mac for this.
  Expected: `All repository tests passed.`

- [ ] **Step 5: Mutation check.** Temporarily add `x=$((` to `script/test`; `./script/test` must fail in shell-syntax. Revert.

- [ ] **Step 6: Commit** (only when the operator has said to commit in this session)
  ```bash
  git add -A && git commit -m "feat: repository skeleton, docs seed and test harness"
  ```

---

### Task 2: CI static job and workflow policy test

**Files:**
- Create: `.github/workflows/validate.yml`
- Create: `tests/placement-policy.sh`
- Modify: `script/test` (append `placement-policy`)

**Interfaces:**
- Produces: workflow job `static` on `ubuntu-24.04` with env `REQUIRE_LINTERS: "1"`, `REQUIRE_CHEZMOI: "1"`, `permissions: contents: read`. Later tasks add assertions to `tests/placement-policy.sh` and a second job `integration` (Task 13).

- [ ] **Step 1: Write the failing test** `tests/placement-policy.sh`, section "workflows":
  ```bash
  # every `uses:` is pinned to a full commit SHA
  refute_match 'uses:[[:space:]]+[^#[:space:]]+@(v[0-9]|main|master|latest)' "$ROOT/.github/workflows"
  assert_match 'uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}' "$ROOT/.github/workflows"
  # nothing floats, nothing is piped into a shell
  refute_match '@latest' "$ROOT/.github/workflows"
  refute_match '(curl|wget)[^|]*\|[[:space:]]*(ba|z)?sh' "$ROOT/.github/workflows" "$ROOT/script" "$ROOT/bootstrap"
  ```
- [ ] **Step 2: Run** `bash tests/placement-policy.sh` — Expected: FAIL (no workflows directory).
- [ ] **Step 3: Write `validate.yml`.** Job `static`: checkout (pinned SHA — copy the SHA setup-dev-mac uses for `actions/checkout`, re-verify it's current), `apt-get install -y shellcheck yamllint zsh`, Go-installed pinned tools exactly as setup-dev-mac's workflow does (`mvdan.cc/sh/v3/cmd/shfmt@vX`, `github.com/rhysd/actionlint/cmd/actionlint@vX`, `github.com/zricethezav/gitleaks/v8@vX`, `github.com/twpayne/chezmoi/v2@vX` — current versions looked up at implementation), then `./script/test`.
- [ ] **Step 4: Run** `bash tests/placement-policy.sh` — Expected: PASS. Run `actionlint` — clean.
- [ ] **Step 5: Commit** `ci: static validation job with pinned actions and tools`

---

### Task 3: Platform detection and preflight guards

**Files:**
- Modify: `script/lib/common.sh`
- Create: `tests/platform.sh`, `tests/fixtures/os-release/{ubuntu-26.04,ubuntu-24.04,debian-13}`, `tests/fixtures/osrelease/{wsl,plain}`
- Modify: `script/test` (append `platform`)

**Interfaces:**
- Produces (all in `common.sh`; file paths overridable for tests via `OS_RELEASE_FILE` default `/etc/os-release`, `KERNEL_OSRELEASE_FILE` default `/proc/sys/kernel/osrelease`, `UNAME_M` default `$(uname -m)`):
  - `detect_target` → prints `wsl` if the kernel osrelease contains `microsoft` (case-insensitive) or `WSL_DISTRO_NAME` is set, else `linux`.
  - `require_target EXPECTED` → dies `Requested --target X but this machine is Y` on mismatch.
  - `require_supported_ubuntu` → dies unless `ID=ubuntu` and `VERSION_ID="26.04"`; message names what was found.
  - `require_x86_64` → dies unless `UNAME_M` is `x86_64`.
  - `is_root` → returns 0 when `EUID` is 0 (factored out so tests can stub it).
  - `require_not_root` → dies if `is_root`, message `Run as your normal user; the scripts call sudo themselves.`
  - `repos_under_mnt` → prints any `.git` directories found under `/mnt/*` to depth 4 (WSL only); used by verify.

- [ ] **Step 1: Write failing tests** in `tests/platform.sh`, each in a subshell sourcing `common.sh` with the env overrides:
  - `detect_target` with `KERNEL_OSRELEASE_FILE=fixtures/osrelease/wsl` (content `6.18.58.1-microsoft-standard-WSL2`) → `wsl`; with `plain` (`6.14.0-15-generic`) and no `WSL_DISTRO_NAME` → `linux`; with `plain` and `WSL_DISTRO_NAME=dev` → `wsl`.
  - `require_supported_ubuntu` passes for `ubuntu-26.04`; `refute_command` for `ubuntu-24.04` and `debian-13`, and the captured stderr contains `24.04` / `debian`.
  - `require_x86_64` passes for `UNAME_M=x86_64`, refused for `aarch64`.
  - `require_not_root` refused when run as `EUID=0` — test by invoking `bash -c 'EUID=0 …'` is impossible (readonly), so test the function's predicate instead: factor `is_root` (returns `[[ ${EUID} -eq 0 ]]`) and stub it in the test.
  - `require_target wsl` refused when `detect_target` says `linux`.
- [ ] **Step 2: Run** `bash tests/platform.sh` — Expected: FAIL (`detect_target: command not found`).
- [ ] **Step 3: Implement** the functions above in `common.sh`. Parse os-release by sourcing it in a subshell (`( . "$OS_RELEASE_FILE"; printf '%s %s\n' "$ID" "$VERSION_ID" )`), not by grep.
- [ ] **Step 4: Run** `bash tests/platform.sh` and `./script/test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: platform detection and preflight guards`

---

### Task 4: Profile catalogue, Brewfiles and render-brewfile

**Files:**
- Create: `script/lib/profiles.sh`, `script/render-brewfile`
- Create: `profiles/core.Brewfile`, `dev.Brewfile`, `security.Brewfile`, `kubernetes.Brewfile`, `backup.Brewfile`, `productivity-extra.Brewfile`, `shell-zsh.Brewfile`, `shell-fish.Brewfile`
- Create: `tests/profiles.sh`, `tests/render-brewfile.sh`
- Modify: `script/test`

**Interfaces:**
- Produces (`profiles.sh`): `DEFAULT_PROFILES="core,dev,security,kubernetes,backup"`; `VALID_PROFILES=(core dev security kubernetes backup productivity-extra)`; `validate_profiles CSV` (ported from setup-dev-mac: non-empty, no empty items, no duplicates, each in `VALID_PROFILES`).
- Produces (`render-brewfile`): `script/render-brewfile [--profiles CSV] [--shell zsh|fish] [--output PATH]`; default output `${XDG_CONFIG_HOME:-$HOME/.config}/setup-dev-linux-wsl/Brewfile`; output starts with `# Generated from reviewed profile fragments. Do not edit directly.`; fragments in order: requested profiles, then `shell-<choice>`.
- Later milestones add `runtime-docker`, `gpu-nvidia`, `ai-agents`, `local-llm` to `VALID_PROFILES` together with their implementation; this task must not list them.

- [ ] **Step 1: Write the Brewfiles.** Every line is `brew "<formula>"  # <purpose>`; copy the purpose comments from the matching setup-dev-mac Brewfile. Contents:
  - `core`: mise, uv, direnv, chezmoi, starship, tmux, ripgrep, fd, fzf, bat, eza, zoxide, atuin, jq, yq, git-delta, btop, just, xh, trash-cli, git-lfs, neovim, gh, age, sops, gitleaks. (No git: apt provides it before Homebrew exists. No gnupg/pinentry-mac: ADR-005. No casks.)
  - `dev`: shellcheck, shfmt, actionlint, yamllint, hadolint, trivy, opencode, codex.
  - `security`: openssl@3.
  - `kubernetes`: copy setup-dev-mac `profiles/kubernetes.Brewfile` formulae verbatim.
  - `backup`: restic, rclone.
  - `productivity-extra`: htop, midnight-commander, rsync (comment: real rsync, unlike macOS openrsync).
  - `shell-zsh`: zsh-autosuggestions, zsh-syntax-highlighting (zsh itself comes from apt). `shell-fish`: fish.
- [ ] **Step 2: Write failing tests.** `tests/render-brewfile.sh`:
  - Every non-blank, non-comment line in `profiles/*.Brewfile` matches `^brew "[a-z0-9@+._-]+"[[:space:]]+# .+$` (purpose comment mandatory); refute `^(cask|tap|mas|vscode)[[:space:]]` and `args:`.
  - Render to a `mktemp` path with defaults; assert header line, `# ---- core.Brewfile ----`, `# ---- shell-zsh.Brewfile ----`; `--shell fish` renders `shell-fish` and not `shell-zsh`.
  - Default-profile cap: count `brew "` entries across the default render ≤ 70.
  - No formula appears twice in the default render.
  - Fail closed: `refute_command` for `--profiles core,,dev`, `--profiles nope`, `--shell bash`, `--output` with no value.
  `tests/profiles.sh`: every name in `VALID_PROFILES` has `profiles/<name>.Brewfile` and vice versa (excluding `shell-*`); every `DEFAULT_PROFILES` item is valid; the profile choice list in `chezmoi/.chezmoi.toml.tmpl` (added in Task 9 — guard with an explicit skip message until that file exists, removed in Task 9) equals `VALID_PROFILES`; the README profile table lists every valid profile.
- [ ] **Step 3: Run** both tests — Expected: FAIL (missing `script/render-brewfile`).
- [ ] **Step 4: Implement** `profiles.sh` and `render-brewfile` (port from setup-dev-mac, dropping `--runtime/--password-manager/--firewall`).
- [ ] **Step 5: Run** `./script/test` — Expected: PASS.
- [ ] **Step 6: Formula availability (verification, not a unit test).** In the CI integration job added by Task 13, a step runs `brew info --formula --json=v2 $(all formulae from the default render + productivity-extra + shell-fish)` and fails on any unknown or Linux-unsupported formula. Any formula that fails gets replaced by its mise equivalent in `chezmoi/dot_config/mise/config.toml.tmpl` (Task 8) and recorded in a new ADR.
- [ ] **Step 7: Commit** `feat: profile catalogue, Linux Brewfiles and renderer`

---

### Task 5: apt base packages and vendor-release check

**Files:**
- Create: `apt/base.list`, `script/apt-base`, `tests/apt.sh`
- Modify: `script/test`, `docs/DECISIONS.md` (ADR-002 records the release check result)

**Interfaces:**
- Produces: `script/apt-base [--check]`. Without flags: `sudo apt-get update` then `sudo apt-get install -y --no-install-recommends` the list. `--check`: prints each missing package (via `dpkg-query -W -f='${Status}'`) and exits 1 if any are missing, 0 otherwise. Reads `APT_BASE_LIST` (default `$ROOT/apt/base.list`).

- [ ] **Step 1: Write `apt/base.list`** — one package per line with `# purpose` comments: `build-essential procps curl file git ca-certificates gnupg socat uidmap unzip zsh locales`. (`gnupg` is for apt key handling, not signing.)
- [ ] **Step 2: Write failing tests** in `tests/apt.sh`: every non-comment line matches `^[a-z0-9][a-z0-9+.-]+[[:space:]]+# .+$`; refute `^(docker\.io|podman-docker|cuda-drivers|nvidia-[a-z0-9-]+)[[:space:]]` in `apt/`; `script/apt-base --check` with `APT_BASE_LIST` pointing at a temp list containing `bash` exits 0 and with `definitely-not-a-package-xyz` exits 1 (runs on any Debian/Ubuntu CI; skip with message when `dpkg-query` is absent unless `REQUIRE_LINTERS=1`).
- [ ] **Step 3: Run** `bash tests/apt.sh` — Expected: FAIL.
- [ ] **Step 4: Implement** `script/apt-base`. It calls `require_not_root` and reads the list with `while read` stripping comments.
- [ ] **Step 5: Run** `./script/test` — Expected: PASS.
- [ ] **Step 6: Vendor release check (one-off, recorded).** Confirm that each of these publishes packages for `resolute` (26.04) on amd64, and record the URL checked and the date in ADR-002: Docker (`download.docker.com/linux/ubuntu/dists/resolute/`), NVIDIA CUDA (`developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/`), NVIDIA Container Toolkit (`nvidia.github.io/libnvidia-container`), Anthropic Claude Code apt repo. If any is missing, stop and switch the Global Constraint and all `26.04` literals in this plan and the code to `24.04`, and note it in ADR-002.
- [ ] **Step 7: Commit** `feat: apt base package list and installer`

---

### Task 6: Homebrew-on-Linux by pinned git clone

**Files:**
- Create: `homebrew/brew.lock`, `script/install-homebrew`, `tests/homebrew.sh`, `chezmoi/.chezmoitemplates/brew-shellenv`
- Modify: `script/lib/common.sh`, `script/test`

**Interfaces:**
- Produces (`common.sh`): `BREW_PREFIX=/home/linuxbrew/.linuxbrew`; `activate_homebrew` (if `$BREW_PREFIX/bin/brew` is executable: `eval "$("$BREW_PREFIX/bin/brew" shellenv)"` with the vendor-init comment; else return 1).
- Produces: `homebrew/brew.lock` with exactly two lines `tag=<X.Y.Z>` and `commit=<40-hex>` (current stable `Homebrew/brew` release, looked up at implementation).
- Produces: `script/install-homebrew [--check]`. Without flags:
  1. `export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1`.
  2. If `$BREW_PREFIX/Homebrew/.git` exists: verify `git -C … rev-parse HEAD` equals the locked commit **or** is a descendant of it (`git merge-base --is-ancestor <commit> HEAD`, which allows Homebrew's own later self-updates); otherwise die: `Homebrew at $BREW_PREFIX does not contain the locked commit; it may be a partial clone. Remove it with: sudo rm -rf $BREW_PREFIX and re-run.` Then skip to step 5.
  3. `sudo install -d -o "$USER" -g "$(id -gn)" "$BREW_PREFIX"`; `git clone --branch <tag> https://github.com/Homebrew/brew "$BREW_PREFIX/Homebrew"`.
  4. Verify `rev-parse HEAD` == locked commit, else remove the clone and die. `mkdir -p "$BREW_PREFIX/bin"`; `ln -sf ../Homebrew/bin/brew "$BREW_PREFIX/bin/brew"`.
  5. `activate_homebrew`; `brew analytics off`; `brew update --quiet`.
  `--check`: brew executable present, `brew analytics state` reports disabled, exit 0/1.
- Produces (`brew-shellenv` template): the zsh/bash snippet evaluating `/home/linuxbrew/.linuxbrew/bin/brew shellenv` guarded by `-x`.

- [ ] **Step 1: Write failing tests** `tests/homebrew.sh`:
  - lock file has exactly `^tag=[0-9]+\.[0-9]+\.[0-9]+$` and `^commit=[0-9a-f]{40}$`.
  - `script/install-homebrew` contains `merge-base --is-ancestor` and `rev-parse HEAD`; refute `install.sh` and `raw.githubusercontent.com/Homebrew/install`.
  - Partial-clone guard (Review Focus 5): create a temp git repo with one unrelated commit at a temp prefix, run `BREW_PREFIX=<tmp> script/install-homebrew` and assert it exits non-zero with stderr containing `partial clone`. (`BREW_PREFIX` must therefore be overridable by env, defaulting to the constant.)
  - `HOMEBREW_NO_ANALYTICS=1` exported before the first `brew` invocation: the line number of the export is less than the first line matching `brew ` in the script.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `install-homebrew`, `activate_homebrew`, the lock and the template.
- [ ] **Step 4: Run** `./script/test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: install Homebrew on Linux from a pinned commit`

---

### Task 7: Package installation from Brewfiles

**Files:**
- Create: `script/packages`
- Modify: `tests/render-brewfile.sh`

**Interfaces:**
- Consumes: `script/render-brewfile`, `activate_homebrew`.
- Produces: `script/packages [--profiles CSV] [--shell zsh|fish] [--check]`. Renders to the default output, then `brew bundle install --file <rendered>`; `--check` runs `brew bundle check --file <rendered> --verbose` and exits with its status.

- [ ] **Step 1: Write failing test** (append to `tests/render-brewfile.sh`): `script/packages` passes `--profiles` and `--shell` through to `render-brewfile` (grep), and contains `brew bundle check`; `refute_match 'brew bundle (cleanup|dump)'` (nothing is uninstalled automatically).
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `./script/test` — PASS.
- [ ] **Step 5: Commit** `feat: install packages from rendered Brewfile`

---

### Task 8: mise runtimes and uv

**Files:**
- Create: `chezmoi/dot_config/mise/config.toml.tmpl`, `chezmoi/run_onchange_after_20_configure-runtimes.sh.tmpl`
- Modify: `tests/placement-policy.sh`

**Interfaces:**
- Produces: the mise config ported from `setup-dev-mac/chezmoi/dot_config/mise/config.toml.tmpl` with the same runtime set and exact versions; Apple-only settings removed with a comment. The run_onchange hook ported from the Mac's `run_onchange_after_20`, using the `brew-shellenv` template, running `mise install` (locked versions) and nothing else.

- [ ] **Step 1: Write failing tests** in `tests/placement-policy.sh`: refute `"latest"` and `= *"lts"` in the mise config; refute `/opt/homebrew` anywhere under `chezmoi/`; assert the hook contains `mise install`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Port the two files.** **Step 4: Run** `./script/test` — PASS.
- [ ] **Step 5: Commit** `feat: mise runtimes ported from setup-dev-mac`

---

### Task 9: chezmoi data template and template test harness

**Files:**
- Create: `chezmoi/.chezmoi.toml.tmpl`, `chezmoi/.chezmoiignore`, `tests/chezmoi-templates.sh`, `tests/fixtures/chezmoi/{wsl,linux,full}.toml`
- Modify: `tests/profiles.sh` (remove the Task 4 skip), `script/test`

**Interfaces:**
- Produces chezmoi data keys (used by every later template): `gitName`, `gitEmail`, `gitSigningMethod` (choices `ssh|gpg|none`, default `ssh`), `gitSigningKey` (default `~/.ssh/id_ed25519.pub`), `workGitDir` (default `~/work`), `workGitEmail` (default empty = no split), `profiles` (multichoice of `VALID_PROFILES`, default = `DEFAULT_PROFILES`), `shell` (`zsh|fish`, default `zsh`), `target` (detected, not prompted: `wsl` when `.chezmoi.kernel.osrelease | lower | contains "microsoft"`, else `linux`), `ephemeral` (from `CI`/`CODESPACES` env, as on the Mac), `machineName` (`.chezmoi.hostname`). `[git] autoCommit=false autoPush=false`, `[diff] pager="delta"`, `sourceDir = {{ dir .chezmoi.sourceDir | quote }}`.
- Produces `tests/chezmoi-templates.sh`: for each fixture, `chezmoi execute-template --config <fixture> --source "$ROOT/chezmoi"` over every `*.tmpl` under `chezmoi/` (excluding `.chezmoi.toml.tmpl`, which is executed with `--init --promptDefaults` plus `--promptString gitName=Test,gitEmail=test@example.invalid` **[verify these chezmoi flags against the pinned version]**), failing on any template error. Skip with message when chezmoi is absent unless `REQUIRE_CHEZMOI=1`. Exposes a helper `render FIXTURE TEMPLATE_PATH` (prints the rendered text) for later tasks' assertions.

- [ ] **Step 1: Write failing tests:** the three fixtures execute cleanly; `render linux.toml` of `.chezmoi.toml.tmpl` under `--init` yields `gitSigningMethod = "ssh"`; refute `.chezmoi.sourceDir` used without `dir` in any template (port the Mac assertion); `tests/profiles.sh` catalogue equality now active.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** `.chezmoi.toml.tmpl` (port the Mac file; drop runtime/passwordManager/firewall/applyMacOSDefaults/scutil; add `target`) and `.chezmoiignore` (ignore `README.md`, `AGENTS.md`). **Step 4: Run** `./script/test` — PASS.
- [ ] **Step 5: Commit** `feat: chezmoi data template and template tests`

---

### Task 10: Shell, prompt and terminal tool dotfiles ported from the Mac

**Files:**
- Create: `chezmoi/dot_zshrc.tmpl`, `chezmoi/dot_config/fish/config.fish.tmpl`, `chezmoi/dot_config/starship.toml`, `chezmoi/dot_config/atuin/config.toml`, `chezmoi/dot_config/ripgrep/ripgreprc`, `chezmoi/dot_tmux.conf`, `chezmoi/dot_local/bin/executable_conn`, `chezmoi/run_onchange_after_30_report-login-shell.sh.tmpl`
- Modify: `tests/placement-policy.sh`, `tests/chezmoi-templates.sh`

**Interfaces:**
- Consumes: `brew-shellenv` template, data keys from Task 9.
- Produces: shells with the Mac's behaviour. Port each file from `setup-dev-mac/chezmoi/`, then remove: `/opt/homebrew` logic (use the template), Rancher/Colima/krew-on-Mac branches tied to runtimes not present here (keep krew PATH under `kubernetes`), `local-llm` lmstudio PATH, macOS-only aliases. Keep: telemetry block, atuin-after-fzf ordering, fzf/fd vars, `GPG_TTY`, eza/bat aliases (on Ubuntu Homebrew provides `bat` as `bat`, not `batcat`), `RIPGREP_CONFIG_PATH`. `conn` is copied verbatim plus its provenance header. The login-shell hook prints, when `$SHELL` isn't the selected shell, exactly one instruction: `chsh -s /usr/bin/zsh` (or the fish path from `command -v fish`) and never runs it.

- [ ] **Step 1: Write failing tests** (placement-policy):
  - the four telemetry variables appear in both rendered shells with identical values (render both via `render linux.toml`, extract `HOMEBREW_NO_ANALYTICS|AZURE_CORE_COLLECT_TELEMETRY|CHECKPOINT_DISABLE|DO_NOT_TRACK` assignments, normalise `export X=1`/`set -gx X 1`, compare sorted sets).
  - in each rendered shell, the line number of the atuin init is greater than that of the fzf init.
  - refute `UseKeychain|osxkeychain|pinentry-mac|/opt/homebrew|scutil|defaults write` anywhere under `chezmoi/` (code lines only: filter `^[[:space:]]*#`).
  - the login-shell hook does not contain a non-comment line starting with `chsh` or `sudo chsh`.
  - `zsh -n` passes on the rendered `.zshrc` and `conn` (shell-syntax already covers `conn` via `--zsh`); `fish --no-execute` on the rendered fish config when fish is installed (same skip rule).
- [ ] **Step 2: Run** — FAIL. **Step 3: Port the files.** **Step 4: Run** `./script/test` — PASS.
- [ ] **Step 5: Commit** `feat: port shell, prompt and terminal dotfiles from setup-dev-mac`

---

### Task 11: Git, SSH and per-machine signing identity

**Files:**
- Create: `chezmoi/dot_gitconfig.tmpl`, `chezmoi/dot_config/git/config-work.tmpl`, `chezmoi/private_dot_ssh/config.tmpl`, `chezmoi/run_onchange_after_12_ssh-key.sh.tmpl`, `chezmoi/run_onchange_after_13_allowed-signers.sh.tmpl`, `script/identity`
- Modify: `tests/chezmoi-templates.sh`, `tests/placement-policy.sh`, `docs/OPERATIONS.md`

**Interfaces:**
- Consumes: data keys `gitName gitEmail gitSigningMethod gitSigningKey workGitDir workGitEmail`.
- Produces:
  - `.gitconfig`: ported from the Mac; with `gitSigningMethod=ssh`: `[gpg] format = ssh`, `[gpg "ssh"] allowedSignersFile = ~/.config/git/allowed_signers`, `[user] signingkey = <gitSigningKey>` (a file path), `[commit] gpgsign = true`, `[tag] gpgsign = true`; `[core] autocrlf = false`; `includeIf "gitdir:<workGitDir>/"` → `~/.config/git/config-work` only when `workGitEmail` is non-empty; no credential helper other than `gh auth git-credential` for `https://github.com`.
  - `.ssh/config`: ported from the Mac; `Include ~/.ssh/config.d/*` first; same algorithm allowlists, `IdentitiesOnly yes`, `ForwardAgent no`; `IdentityFile ~/.ssh/id_ed25519`; no `UseKeychain`, no `IdentityAgent`.
  - `run_onchange_after_12_ssh-key`: if `~/.ssh/id_ed25519` is absent, `ssh-keygen -t ed25519 -a 100 -N '' -C "<user>@<hostname>"`; prints the public key and where to enrol it **twice** (GitHub: as an Authentication key and as a Signing key). Never overwrites an existing key.
  - `run_onchange_after_13_allowed-signers`: writes `~/.config/git/allowed_signers` as `<gitEmail> <contents of ~/.ssh/id_ed25519.pub>` (plus `<workGitEmail> …` when set). Generated locally; not tracked.
  - `script/identity --check`: key exists with mode 600; `git config gpg.format` is `ssh`; signing works: in a `mktemp -d` repo, `git commit --allow-empty -m test` succeeds and `git verify-commit HEAD` succeeds; prints the enrolment reminder if `ssh -T git@github.com` does not authenticate (non-fatal, network-dependent).

- [ ] **Step 1: Write failing tests:**
  - render `.gitconfig` with `linux.toml` (ssh, no work email): contains `format = ssh`, `allowedSignersFile`, `autocrlf = false`; does not contain `includeIf`. With `full.toml` (work email set): contains `includeIf "gitdir:`. With a fixture override `gitSigningMethod=gpg`: contains `format = openpgp`.
  - render `.ssh/config`, write it to a temp file, and run `ssh -G -F <file> example.invalid` — exits 0 (proves Ubuntu's ssh accepts it), output contains `identitiesonly yes` and `forwardagent no`.
  - the ssh-key hook contains `[[ -f` guard before `ssh-keygen` and refutes `-N ''` being combined with an existing-key overwrite (`-f` with `-y`/`rm`).
  - Integration (Task 13): `./script/identity --check` passes after apply.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement/port.** **Step 4: Run** `./script/test` — PASS.
- [ ] **Step 5: Docs:** `docs/OPERATIONS.md` section "Enrol this machine's SSH key" (auth + signing, the `git remote set-url` switch to ssh, how to revoke a lost machine's key).
- [ ] **Step 6: Commit** `feat: per-machine SSH identity and SSH commit signing`

---

### Task 12: bootstrap entrypoint and verify

**Files:**
- Create: `bootstrap`, `script/verify`, `tests/bootstrap.sh`
- Modify: `script/test`, `README.md`, `docs/OPERATIONS.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `./bootstrap plan|apply [--target wsl|linux] [--profiles CSV] [--shell zsh|fish] [--non-interactive]`.
  - Order: `require_bash5` → `require_not_root` → `require_x86_64` → `require_supported_ubuntu` → `require_target` (default: detected) → `validate_profiles` → `script/apt-base` → `script/install-homebrew` → `script/packages` → `chezmoi init --source "$ROOT/chezmoi" --apply` (with `--promptDefaults` under `--non-interactive`; chezmoi's own prompts otherwise; existing managed targets are backed up with `backup_file` before chezmoi first writes them — implement by running `chezmoi diff --no-pager` names first and backing up each existing target that would change) → `script/verify`.
  - `plan` prints each step and what it would change (`apt-base --check`, `install-homebrew --check`, `packages --check`, `chezmoi diff`) and changes nothing.
  - Exit codes: 0 success, 1 failure.
- Produces: `script/verify` — runs and reports each, exit 1 if any fails: platform guards; `apt-base --check`; `install-homebrew --check`; `packages --check`; `mise ls --missing` empty; `uv --version`; `chezmoi verify` (no drift); `script/identity --check`; login-shell report (informational); on `wsl` target, `repos_under_mnt` empty.

- [ ] **Step 1: Write failing tests** `tests/bootstrap.sh`: `refute_command` for `./bootstrap`, `./bootstrap apply --target mac`, `./bootstrap apply --profiles nope`, `./bootstrap apply --shell bash`; `./bootstrap plan` under fixture overrides for an unsupported OS exits non-zero before printing any step (stderr names the OS); the step order in `bootstrap` (grep line numbers) is guards → apt-base → install-homebrew → packages → chezmoi → verify.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `./script/test` — PASS.
- [ ] **Step 5: Docs:** README quick start; OPERATIONS "New machine (Linux)", "New machine (WSL, run by setup-dev-win)", "Re-running safely"; ARCHITECTURE current-state flow.
- [ ] **Step 6: Commit** `feat: bootstrap entrypoint and verification`

---

### Task 13: x86_64 integration job (the milestone proof)

**Files:**
- Modify: `.github/workflows/validate.yml`, `tests/placement-policy.sh`

**Interfaces:**
- Produces: job `integration` on `ubuntu-24.04` (x86_64) running `container: ubuntu:26.04`:
  1. As root in the container: `apt-get update && apt-get install -y sudo git ca-certificates`; create user `dev` with passwordless sudo (CI only); copy the checkout to `/home/dev/setup-dev-linux-wsl` owned by `dev`.
  2. Seed `/home/dev/.gitconfig` with `[user] name = seed` (Review Focus 4).
  3. As `dev` (`sudo -u dev -H bash -lc …`): `CI=1 ./bootstrap apply --target linux --non-interactive` with `--promptString gitName=CI,gitEmail=ci@example.invalid` passed through to chezmoi.
  4. Assert a `~/.gitconfig.backup.*` exists.
  5. `./script/verify` passes.
  6. Formula availability step from Task 4 Step 6.
  7. Idempotency (Review Focus 1): run `./bootstrap apply …` again; assert `chezmoi diff` is empty, `git -C /home/linuxbrew/.linuxbrew/Homebrew rev-parse HEAD` unchanged from step 3, `~/.ssh/id_ed25519` mtime unchanged.
  8. Refusals (Review Focus 2): `sudo ./bootstrap plan` exits non-zero with `normal user` in stderr.

- [ ] **Step 1: Write failing policy test:** `tests/placement-policy.sh` asserts the workflow contains a job named `integration` using `container: ubuntu:26.04`, and that passwordless sudo appears only inside `.github/workflows/` (refute `NOPASSWD` under `script/`, `bootstrap`, `chezmoi/`).
- [ ] **Step 2: Run** — FAIL. **Step 3: Add the job.** **Step 4: Push to a branch** (only with the operator's go-ahead to create the GitHub repo and push) and confirm both jobs green. Until then, run the same steps locally in a container: `docker run --rm --platform linux/amd64 -v "$PWD":/src ubuntu:26.04 …` (needs x86 emulation in Colima; if unavailable, say so and rely on CI).
- [ ] **Step 5: Commit** `ci: x86_64 integration job proving bootstrap, verify and idempotency`

---

## Self-review notes

- Spec coverage for milestone 1: §7.1 targets/fallback (Tasks 3, 5), §7.2 layout (all), §7.3 order (Tasks 5–9, 12), §7.4 Brewfile profiles (Task 4; apt/script-backed profiles deferred to milestone 2 by design), §7.5 dotfiles + identity (Tasks 10, 11), §7.10 tests/CI (Tasks 1, 2, 13), §8.4 telemetry (Task 10), §8.5 line endings (Task 1). Deferred to later plans: §7.6 WSL integration (`/etc/wsl.conf`, wrappers), §7.7 Docker, §7.8 GPU, §7.9 agents, §8.2 relay, `update-report`, `test-install`.
- Names used across tasks: `activate_homebrew`, `BREW_PREFIX`, `detect_target`, `require_*`, `render` (test helper), `validate_profiles`, `DEFAULT_PROFILES`, `VALID_PROFILES` — consistent.
