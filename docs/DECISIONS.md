# Decisions

Durable architectural decisions. Section references are to
`docs/superpowers/specs/2026-11-24-setup-dev-win-linux-design.md`.

## ADR-001: Two repositories, this one Linux-only

Status: accepted. Spec section 3.

The Windows and Linux halves live in separate repositories, so each follows its
platform's conventions. This repository covers Ubuntu only. It is unrelated to the
operator's existing `istvano/setup-dev-linux`, which is never modified or depended
on.

## ADR-002: Ubuntu 26.04 x86_64 only, with a release fallback rule

Status: accepted. Spec section 7.1.

Only Ubuntu 26.04 LTS on x86_64 is supported; there are no arm64 branches. Any other
distro or release fails closed before changes. If a vendor repo needed by a default or
`gpu-nvidia` profile has no 26.04 packages, the whole repo targets 24.04 LTS for v1.
Repos from different Ubuntu releases are never mixed.

Release check, 2026-11-24 (HTTP 200 for every URL; all four vendors support 26.04, so the
repo stays on 26.04):

- Docker: `https://download.docker.com/linux/ubuntu/dists/resolute/Release` (Suite
  `resolute`, amd64 listed) and `.../resolute/stable/binary-amd64/Packages` (`docker-ce`
  present).
- NVIDIA CUDA: `https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/`
  and its `Release` (dated 2026-11-18) and `Packages`.
- NVIDIA Container Toolkit: `https://nvidia.github.io/libnvidia-container/stable/deb/amd64/Packages`
  and `.../stable/deb/nvidia-container-toolkit.list`. This repo is one release-agnostic
  flat repo (`deb ... $(ARCH) /`), so it has no 26.04 suite to be missing.
- Anthropic Claude Code: documented at https://code.claude.com/docs/en/setup as
  `deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main`.
  `https://downloads.claude.ai/claude-code/apt/stable/dists/stable/Release` and
  `.../main/binary-amd64/Packages` return 200. The suite is `stable`, not an Ubuntu
  codename, so it is distro-agnostic and has no 26.04 gap.

## ADR-003: apt base, vendor apt, Homebrew CLI, mise runtimes

Status: accepted. Spec section 3.

apt supplies the small base and vendor repos (Docker, NVIDIA, Anthropic). Homebrew on
Linux supplies CLI tools through composable profile Brewfiles, keeping the macOS
repo's profile model. mise manages language runtimes and uv manages Python.

## ADR-004: Homebrew by pinned git clone, no install script

Status: accepted. Spec section 7.3 and section 3.

Homebrew is installed by cloning `Homebrew/brew` at a pinned release tag and commit
into its prefix, which is Homebrew's documented alternative install. No
`curl ... | sh` appears anywhere, including CI. If the pinned clone proves
unsupported, the fallback is the official installer downloaded, reviewed against a
pinned hash, then run, documented as the single remote-script exception.

What the pin does and does not anchor: it verifies the FIRST clone only (HEAD must
equal the locked commit, or the clone is removed). `script/install-homebrew` then
runs `brew update` on every apply, which moves Homebrew forward to whatever upstream
publishes, and a later run accepts any HEAD that descends from the locked commit.
From then on Homebrew's own update channel is trusted, as it is on every Homebrew
installation; the pin is a reviewed starting point, not a freeze.

## ADR-005: SSH commit signing with per-machine keys

Status: accepted. Spec section 7.5.

Commits are signed with SSH using a per-machine `~/.ssh/id_ed25519` that is never
copied between machines. This deliberately differs from setup-dev-mac ADR-017. The
work identity is split with `includeIf gitdir:`, and `core.autocrlf` is false.

## ADR-006: Telemetry opt-outs carried from setup-dev-mac

Status: accepted. Spec section 8.4. Carried from setup-dev-mac ADR-046.

No tool reports usage to its vendor where a verified opt-out exists. Both shells
carry exactly `HOMEBREW_NO_ANALYTICS=1`, `AZURE_CORE_COLLECT_TELEMETRY=false`,
`CHECKPOINT_DISABLE=1` and `DO_NOT_TRACK=1`, and a test compares them. A variable
nothing reads is worse than none.

## ADR-007: Login shell reported, never changed

Status: accepted. Spec section 6.9.

zsh is the default interactive shell and fish the exclusive alternative. The
repository reports the account's login shell but never runs `chsh` or edits
`/etc/shells`; changing it is the operator's decision.

## ADR-008: One tool per job, default-profile cap of 70

Status: accepted. Carried from setup-dev-mac ADR-022.

Before adding a tool, check whether an installed one covers the use case. The
default profiles together may contain at most 70 entries, a cap enforced by a test
once profiles exist.

## ADR-009: codex via mise (aqua) on Linux

Status: accepted.

Context: `codex` was listed as a Homebrew formula in the dev profile. It is a cask
only, and the cask has no Linux build, so `brew bundle` failed on x86_64 Ubuntu. The
integration rehearsal on 2026-11-24 found it, which is what the formula-availability
check is for.

Decision: the dev profile no longer lists `codex` in `profiles/dev.Brewfile`. It is
pinned in `chezmoi/dot_config/mise/config.toml.tmpl` as `"aqua:openai/codex"`, inside
the `dev` gate, at an exact version. No download-and-run script is involved.

Trust, stated as it is: the pin fixes the VERSION, not the content. The aqua registry
entry for `openai/codex` (`pkgs/openai/codex/registry.yaml`, checked 2026-11-24)
declares no checksum, attestation, cosign, SLSA or minisign verification, so aqua
verifies nothing about the archive beyond what GitHub's TLS gives: the content is
whatever the `rust-v<version>` release asset is when it is downloaded. A replaced
release asset would be accepted. Pinning its SHA-256 (for example through a mise
lockfile with checksums) is an open task in `TASKS.md`.

Consequences: updates are pin bumps in that file, not `brew upgrade`. The upstream
tag is `rust-v<version>`; the aqua registry strips the prefix, so the pin is the bare
version. `tests/placement-policy.sh` asserts the pin and that it is not floating.

## ADR-010: Opt-in security-scan, cloud and docs profiles; krew plugins

Status: accepted. From the comparison of the operator's older Linux repositories and
setup-dev-mac with this one.

Decision: five opt-in profiles join `VALID_PROFILES`, none in `DEFAULT_PROFILES`, so
the 70-entry default cap (ADR-008) is untouched: `security-scan` (syft, grype,
osv-scanner, trufflehog, dive, cosign, nmap), `cloud` (opentofu, terraform-docs,
terragrunt), `cloud-aws` (awscli, granted), `cloud-azure` (kubelogin) and `docs` (d2,
pandoc). Every formula was checked on 2026-11-24 against `formulae.brew.sh` for an
`x86_64_linux` bottle; CI's formula-availability step now renders all of them.

Deferred, with the reason: `cloud-gcp` is not created. `gcloud-cli` is a cask in
homebrew-core (a macOS archive and installer script) and there is no Linux formula.
`azure-cli` is likewise a macOS-only cask now (its download is the `macos-arm64`
tarball), so `cloud-azure` carries `kubelogin` alone, which is a standalone binary.
Both come from the vendors' signed apt repositories with the vendor-apt machinery, and
both are in `TASKS.md`. setup-dev-mac lists `azure-cli` as a formula; that line does
not resolve today (reported to the operator, not touched from here).

krew: the `kubernetes` profile (default) installs `neat`, `view-secret`, `tree`,
`whoami` and `images` through `run_onchange_after_28_krew-plugins`, a narrow exception
to ADR-003 because krew's index pins each plugin's version and URL. All five publish
linux/amd64. A failed install fails the hook so chezmoi retries it on the next apply,
as the runtimes hook does. `sniff` and `popeye` from the Mac list are not carried:
sniff needs packet-capture privileges in the pod and popeye is stale.

Also: `wget` and `libxml2-utils` join the apt base (the curl-pipe-shell refutation
concerns pipes, not the package), and `docs/DROPPED.md` records tools deliberately
not adopted, so the question is not reopened by accident.
