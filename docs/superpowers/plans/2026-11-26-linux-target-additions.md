# Linux-target additions (moved from setup-dev-linux) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** setup-dev-linux-wsl installs every command-line item that setup-dev-linux will stop installing, so a Linux machine set up by `setup-dev-linux` + `./bootstrap apply --target linux` loses nothing.

**Architecture:** A new `script/apt-vendor` installs signed vendor apt repositories (keys committed with asserted fingerprints, deb822 sources) and their packages, per profile and target, run by bootstrap after `apt-base`. New profiles `runtime-docker` (Docker Engine, linux target), `ai-agents` (Claude Code from Anthropic's apt repo), `cloud-gcp` (gcloud), `gpu-nvidia` (NVIDIA Container Toolkit, linux target); `cloud-azure` gains azure-cli. Small CLI tools join existing Brewfiles; the Copilot CLI joins mise.

**Tech Stack:** bash (set -Eeuo pipefail), apt/deb822, gpg, Homebrew on Linux, mise, chezmoi, the repo's tests/*.sh.

**Spec:** `/Users/istvano/workspace/setup-dev-linux/docs/superpowers/specs/2026-11-26-linux-host-refactor-design.md` (section "What moves where", decisions 3, 8; review calls on Claude Code, the NVIDIA toolkit and Docker scope), plus this repo's own spec sections 7.7-7.9 where they do not conflict (latest stable per ADR-011 replaces "versions pinned"; Docker ports reachable from the network on the linux target per the operator).

## Global Constraints

- Branch `host-handoff-additions` from `main`. Commit per task with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Gate after every task: `REQUIRE_CHEZMOI=1 ./script/test` on the host; new shell also passes shellcheck at CI's version (`docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash -c 'apt-get update -qq && apt-get install -y -qq shellcheck >/dev/null && ./script/shell-files | xargs shellcheck -x'`) and shfmt `-i 2 -ci`. Tests fail rather than skip under REQUIRE_LINTERS=1.
- Latest stable (ADR-011): no package version pins; vendor packages install the repository's current version.
- Vendor keys committed under `apt/keys/<id>.asc`; each fingerprint asserted by a test; installed to `/etc/apt/keyrings/<id>.asc`; sources written as `/etc/apt/sources.list.d/<id>.sources` (deb822, `Signed-By:` that keyring). Never `apt-key`, never a download-and-run script, never `curl | sh`.
- Fingerprints (from setup-dev-linux `manifest/repositories.json`, verify each against the downloaded key before committing it): docker `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`; azure-cli `BC528686B50D79E339D3721CEB3E94ADBE1229CF` (take the full value from the source file); google-cloud-cli `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`; nvidia-container-toolkit `C95B321B61E88C1809C4F759DDCAE044F796ECB0`; Anthropic `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE` (setup-dev-linux `manifest/keys/claude-desktop.asc`, uid "Anthropic Claude Code Release Signing").
- One keyring file per vendor and one `Signed-By` per URI: APT refuses all sources if one URI appears twice with different `Signed-By` (setup-dev-linux hit this with claude-desktop and chatgpt). The Anthropic keyring id is `anthropic`, so the host repository can reuse the same file.
- Target rules: `runtime-docker` and `gpu-nvidia` are linux-target only for now (Docker inside WSL stays in the WSL milestone with appendWindowsPath=false and the `code` wrapper); bootstrap refuses them on `--target wsl` with a message naming that milestone. Other new profiles work on both targets.
- Default profiles stay within the 70-entry cap (ADR-008); new default entries: midnight-commander, fastfetch (core), cilium-cli, hubble (kubernetes).
- Docker on the linux target: rootful dockerd under systemd; the operator added to the `docker` group (documented as root-equivalent); remove `docker.io` and `podman-docker` first; `/etc/docker/daemon.json` sets only `{"log-driver": "local"}` (ports stay reachable from the network, operator decision; no loopback binding on this target).
- Never run as root; scripts call sudo themselves (existing pattern in script/apt-base).

## Review Focus

1. A machine where Docker's or Microsoft's source already exists (e.g. from the vendor's own instructions) with a different keyring: apt-vendor must detect a conflicting source for the same URI and stop with a message naming the file to remove, not leave APT broken. Test in Task 1.
2. A downloaded key whose fingerprint does not match the committed one (or a committed key file that was edited): refuse before writing any source. Test in Task 1.
3. Re-running bootstrap: apt-vendor is idempotent (no duplicate sources, no rewrite when identical) and `--check` reports drift without sudo. Test in Task 1.
4. `--profiles ...,runtime-docker` on `--target wsl`: refused up front with the milestone message, before any step runs. Test in Task 2.
5. Removing a profile later (e.g. dropping cloud-gcp): nothing is uninstalled (repo convention), and verify does not demand it. Test in Task 4.

---

### Task 1: script/apt-vendor and the vendor repository catalogue

**Files:** Create `apt/vendor.list` (one line per repository: `id profile target uri suite components packages...`, or a small deb822-like data file; your choice, documented in its header), `apt/keys/{docker,microsoft,google-cloud,nvidia-container-toolkit,anthropic}.asc`, `script/apt-vendor`, `tests/apt-vendor.sh`; modify `script/test` (register), `bootstrap` (run after apt-base: `run_step "vendor apt" "$ROOT/script/apt-vendor" --profiles "$profiles" --target "$target"`), `script/verify` (vendor packages of selected profiles installed).

**Interfaces:** Produces `script/apt-vendor --profiles CSV --target wsl|linux [--check]`; repository ids `docker`, `azure-cli`, `google-cloud-cli`, `nvidia-container-toolkit`, `anthropic`.

- [ ] Step 1: failing tests (fakes for sudo/apt-get/gpg/dpkg-query on PATH, a temp root via env overrides for /etc/apt paths): each committed key's fingerprint equals the constant; a key with a different fingerprint is refused before any write; the rendered `.sources` for docker has `Types: deb`, `URIs: https://download.docker.com/linux/ubuntu`, `Suites: <codename>`, `Components: stable`, `Signed-By: /etc/apt/keyrings/docker.asc`; only repositories of selected profiles and the current target are written; a second run writes nothing; an existing source for the same URI with another `Signed-By` stops with a message naming the file; `--check` lists missing packages and exits 1 without calling sudo.
- [ ] Step 2: run the tests; expect failure.
- [ ] Step 3: implement (keys copied from the vendors' published URLs or the setup-dev-linux key files, fingerprints verified with `gpg --show-keys --with-colons`).
- [ ] Step 4: run the gate; expect pass.
- [ ] Step 5: commit `feat(apt): signed vendor repositories per profile (script/apt-vendor)`.

### Task 2: Profiles runtime-docker, ai-agents, cloud-gcp, gpu-nvidia; azure-cli in cloud-azure

**Files:** Modify `script/lib/profiles.sh` (VALID_PROFILES gains `runtime-docker`, `ai-agents`, `cloud-gcp`, `gpu-nvidia`; DEFAULT_PROFILES unchanged), `chezmoi/.chezmoi.toml.tmpl` profile choices, README profile table, `bootstrap` (refuse runtime-docker and gpu-nvidia on wsl with: `<profile> is for --target linux for now; Docker and GPU inside WSL arrive with the WSL integration milestone (TASKS.md).`), `apt/vendor.list` mappings (runtime-docker→docker, ai-agents→anthropic, cloud-gcp→google-cloud-cli, cloud-azure→azure-cli, gpu-nvidia→nvidia-container-toolkit), empty `profiles/<name>.Brewfile` where the catalogue test requires one (with a header saying the packages come from apt-vendor); tests/profiles.sh and tests/bootstrap.sh.

- [ ] Step 1: failing tests: the four profiles are valid and appear in all four catalogue places; `--target wsl --profiles core,runtime-docker` exits non-zero with the message above before any step; cloud-azure selects azure-cli.
- [ ] Step 2-4: run, implement, gate.
- [ ] Step 5: commit `feat(profiles): runtime-docker, ai-agents, cloud-gcp, gpu-nvidia; azure-cli via vendor apt`.

### Task 3: Docker engine setup on the linux target

**Files:** Create `script/docker-setup` (idempotent: remove `docker.io podman-docker` if installed; write `/etc/docker/daemon.json` = `{"log-driver": "local"}` when different, keeping a timestamped backup; `systemctl enable --now docker`; `usermod -aG docker $USER` when missing, printing that it takes effect at next login and is root-equivalent); `--check` mode; tests `tests/docker-setup.sh`; modify bootstrap (run after apt-vendor when runtime-docker is selected), `script/verify` (dockerd active, user in docker group, daemon.json matches).

- [ ] Step 1: failing tests with fakes: conflicting packages removed first; daemon.json written with exactly `{"log-driver": "local"}` and backed up when it differed; group add only when missing; `--check` reports each item without sudo; nothing runs when runtime-docker is not selected.
- [ ] Step 2-4: run, implement, gate.
- [ ] Step 5: commit `feat(docker): Docker Engine on the linux target (runtime-docker)`.

### Task 4: Copilot CLI, small CLI tools, vim

**Files:** Modify `chezmoi/dot_config/mise/config.toml.tmpl` (`"npm:@github/copilot" = "latest"`), `profiles/core.Brewfile` (`brew "midnight-commander"  # Two-pane terminal file manager (mc).`, `brew "fastfetch"  # System information summary.`), `profiles/kubernetes.Brewfile` (`brew "cilium-cli"  # Cilium CNI management.`, `brew "hubble"  # Cilium network observability CLI.`), `apt/base.list` (`vim  # the classic editor, for scripts and muscle memory; nvim stays the default editor`), placement-policy and render tests, CI formula-availability list.

- [ ] Step 1: failing tests: the four formulae present with purpose comments; default profiles total ≤ 70; mise config contains `"npm:@github/copilot" = "latest"` and passes the ADR-011 spelling check; removing a profile from the selection does not uninstall anything (existing convention, assert verify ignores unselected profiles).
- [ ] Step 2-4: run, implement, gate.
- [ ] Step 5: commit `feat: Copilot CLI, midnight-commander, fastfetch, cilium-cli, hubble, vim`.

### Task 5: Decisions and runbook

**Files:** `docs/DECISIONS.md` (ADR-016 "Vendor apt repositories and the linux-target Docker", covering keys and fingerprints, one keyring per vendor, latest stable, target rules, Docker ports reachable on linux and the note that UFW does not filter Docker's published ports, Claude Code from apt, Copilot via mise, the moved items from setup-dev-linux), `docs/OPERATIONS.md` (new profiles, Docker group note, how to check vendor sources), `docs/ARCHITECTURE.md`, `README.md` (profile table), `TASKS.md` (vendor-apt and linux-target Docker done; WSL Docker, CUDA toolkit, managed agent policy remain), `docs/DROPPED.md` (only if something is not carried over).

- [ ] Step 1: write the docs; every name and command matches the code.
- [ ] Step 2: gate; expect pass.
- [ ] Step 3: commit `docs: vendor apt, linux-target Docker and the items moved from setup-dev-linux`.
