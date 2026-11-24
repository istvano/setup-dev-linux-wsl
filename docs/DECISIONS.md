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
