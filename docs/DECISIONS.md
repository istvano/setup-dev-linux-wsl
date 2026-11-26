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
declared in `chezmoi/dot_config/mise/config.toml.tmpl` as `"aqua:openai/codex"`, inside
the `dev` gate, at `"latest"` (ADR-011; it was an exact pin when this was written). No download-and-run script is involved.

Trust, stated as it is: the version string never fixed the content. The aqua registry
entry for `openai/codex` (`pkgs/openai/codex/registry.yaml`, checked 2026-11-24)
declares no checksum, attestation, cosign, SLSA or minisign verification, so aqua
verifies nothing about the archive beyond what GitHub's TLS gives: the content is
whatever the `rust-v<version>` release asset is when it is downloaded. A replaced
release asset would be accepted. Verifying its SHA-256 (for example through a mise
lockfile with checksums) is an open task in `TASKS.md`.

Consequences: updates come through mise, not `brew upgrade`. ADR-011 supersedes the
original wording "updates are pin bumps": there is no pin. The upstream tag is
`rust-v<version>`; the aqua registry strips the prefix. `tests/placement-policy.sh`
asserts the entry is `"latest"`.

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

## ADR-011: Install the latest stable versions

Status: accepted. Operator decision, 2026-11-25.

Context: the mise config pinned runtimes to release lines (node 24, go 1.26, ...) and
CLIs to exact versions, so a fresh setup installed software that was already behind.

Decision: the setup installs the LATEST STABLE version of every component. In the mise
config, `node = "lts"` (Node's recommended line), `rust = "stable"` (rustup's channel)
and `"latest"` for go, pnpm, python, maven, gradle, kotlin, `"npm:cline"` and
`"aqua:openai/codex"`. Java keeps three LTS major lines side by side (temurin 25 as the
default, then 21 and 17, each resolving to its latest patch) because a JDK major is a
compatibility boundary; 25 became the default by operator decision on 2026-11-26. `tests/placement-policy.sh` asserts that every `[tools]` entry is one of
those spellings and that no tool carries a hard-coded patch version. Prereleases:
checked 2026-11-25 with `mise latest` and `mise ls-remote`; the python core plugin
hides alphas, the npm backend skips nightly dist-tags and the aqua backend lists
releases only, so `"latest"` is safe for all of them.

Homebrew: `homebrew/brew.lock` still anchors the verified first clone (ADR-004), but
`brew update` runs immediately afterwards, so the installed Homebrew is the latest. The
lock is refreshed when Homebrew releases (TASKS.md).

This departs deliberately from setup-dev-mac ADR-045 ("nothing floats"). It supersedes
ADR-009's "updates are pin bumps" for codex and ADR-003's "mise runtimes" scope (versions are now latest).

Trade-off: reproducibility is traded for currency. Two applies on different days can
install different toolchains, and a new release can break a project until it is
checked. mise still verifies checksums where the backend supports it; the aqua codex
entry declares none (ADR-009, TASKS.md). CI's own tools and GitHub Actions remain
pinned.

## ADR-012: The Windows host repository is exempt from the /mnt check

Status: accepted. From the first real WSL run (setup-dev-win milestone 1 acceptance).

On the `wsl` target `script/verify` fails when it finds git repositories under `/mnt`,
because checkouts on the Windows drives are slow and get the wrong permissions and line
endings. The first end-to-end run failed only that check, on the setup-dev-win checkout
that had just driven the install: that repository runs from Windows PowerShell and must
live on a Windows drive.

`repos_under_mnt` skips a repository whose `remote.origin.url`, without a trailing
`.git` or `/`, ends in `/setup-dev-win`. The URL is read from the repository's config
file with `git config --file`, so a checkout owned by the Windows user cannot trip
git's ownership check. Every other repository on `/mnt` still fails, including one with
no origin and one whose name merely starts with `setup-dev-win`.

## ADR-013: llm-relay, an on-demand bridge to LM Studio on Windows

Status: accepted, 2026-11-26, after a manual test on the WSL acceptance machine.

WSL in NAT mode cannot reach a Windows service bound to `127.0.0.1`, and LM Studio's
server stays on Windows' loopback ("Serve on Local Network" off). `llm-relay`
(`~/.local/bin`, from `chezmoi/dot_local/bin/executable_llm-relay`) bridges the two with
nothing on a network interface: socat listens on WSL's `127.0.0.1:<port>` (default 1234)
and, per connection, starts the inbox Windows PowerShell through WSL interop, which
connects to `localhost:<port>` on Windows and copies bytes both ways. `localhost` covers a
server bound to IPv4 or IPv6. The operator runs it in a terminal tab when needed (operator
decision: on demand, not a service); `llm-relay --check` sends one request and says
whether LM Studio answered.

Facts from the test: socat rejects an address as long as an inline encoded PowerShell
command, so socat runs this script's `--pump` mode instead; Windows PowerShell writes its
progress and errors as CLIXML on stderr when redirected, so progress is silenced and
errors go to `~/.local/state/llm-relay.log`. The port is checked to be digits in range,
because it is interpolated into the PowerShell command.

Rejected: WSL mirrored networking and LM Studio on all interfaces (ADR-006 and spec 8.2:
both put services on the LAN); a systemd socket unit (more moving parts than the operator
wanted for an on-demand tool; the same `--pump` mode would serve one later); `netsh
portproxy` (flagged by setup-dev-win's posture report). A faster Windows half (a
hash-pinned `ncat.exe`) is an option if PowerShell's per-connection start-up shows.

## ADR-014: Settings carried over from setup-dev-linux

Status: accepted, 2026-11-26, after a settings comparison with the operator's previous
Linux repository (istvano/setup-dev-linux), desktop elements excluded.

The operator chose to carry over:

- **proxyon / proxyoff** (old D012: keep). `~/.config/zsh/proxy.zsh` and
  `~/.config/fish/functions/proxy{on,off}.fish` export `http_proxy`, `https_proxy`,
  `all_proxy` and `no_proxy` in both cases and restore the previous values, unset state and
  export attributes. The values come from a private, unmanaged file
  (`~/.config/proxy/proxy.local.json`, or `$PROXY_SETTINGS`) read by `proxy-settings`, a
  bash and jq port of the old Python reader with the same rules: regular file, owned by the
  user, mode without group or other access, at most 64 KiB, exactly the four string keys,
  http/https/socks5/socks5h URLs with a host, no control characters or duplicate keys.
  Values are never evaluated.
- **Git shortcuts** (old D012: keep "git"). oh-my-zsh stays dropped; its everyday git
  aliases (`gst`, `gco`, `gcb`, `gd`, `gl`, `gp`, `gpf`, `glog`, `grbi` and others, 21 in
  all) come back as zsh aliases and fish abbreviations, kept identical by a test.
- **Java 25 as the default** (old D011): `java = ["temurin-25", "temurin-21",
  "temurin-17"]` (ADR-011 updated).

Also fixed: `dot_gitconfig.tmpl` pointed `core.excludesfile` at `~/.config/git/ignore`,
which the port from setup-dev-mac had not shipped; `chezmoi/dot_config/git/ignore` now
exists.

Not carried over, by operator choice on 2026-11-26: WSL-side VS Code extensions and a
"moving in" runbook (credential restore, `~/.ssh/config.d` host blocks, private
`.npmrc`), together with `CLINE_NO_AUTO_UPDATE` and `UV_PYTHON_DOWNLOADS`. kubectl keeps
following Homebrew's latest; pin it with mise if clusters fall more than one minor behind.

## ADR-015: Go telemetry off, nvim and bat config, aider (parity with setup-dev-mac)

Status: accepted, 2026-11-26, after a Mac, Windows and WSL parity comparison.

1. **Go telemetry off.** `run_after_31_telemetry-optout` ports setup-dev-mac's
   hook 31 (Go and aider; gcloud is absent here). Go's telemetry defaults to local-only
   counters, so `go telemetry off` declines to collect at all. The hook finds go with
   `mise which go`, never `mise exec`, because `exec` installs a missing toolchain and a
   telemetry opt-out must not download one; it is a no-op when already off and never
   fatal, because chezmoi stops at the first failing script. A test runs it against a stub
   mise that rejects every subcommand but `which go`. It is `run_after_`, not
   `run_onchange_`: because it exits 0 on failure, chezmoi would record it as done after an
   offline first apply (aider not yet installed) and never apply the aider opt-out later.
   Cheap and idempotent (`mise which`, a marker file, no network once set), it re-checks on
   every apply and so self-heals. Hook 29 stays `run_onchange_`; a missed install is retried
   by the next apply that changes the list, or by `uv tool install` by hand.
2. **nvim and bat configuration.** `dot_config/nvim/init.lua` (plugin-free, built-in
   options only) and `dot_config/bat/config` (Catppuccin Mocha, built in to bat) are
   ported unchanged except for the clipboard. Under WSL (`vim.fn.has("wsl")`) nvim sets
   `vim.g.clipboard`: `clip.exe` for copy and `powershell.exe -NoProfile -Command
   Get-Clipboard -Raw` (UTF-8 output, CR stripped) for paste. Both are taken from
   `/mnt/c/Windows/System32` when present, so the bridge survives `appendWindowsPath=false`;
   bare names are the fallback. clip.exe reads the console code page, so non-ASCII copy may
   be garbled (noted in the file). Elsewhere neovim finds its own provider.
3. **aider.** `run_onchange_after_29_uv-tools` runs `uv tool install --force --python 3.12
   aider-chat` for the dev profile, as the Mac does, but UNPINNED: ADR-011 installs the
   latest stable, whereas the Mac pins with `==`. An installed aider is left alone, so a
   re-apply costs no network; `uv tool upgrade aider-chat` moves it. Python 3.12 because
   aider-chat requires below 3.13 and mise's python is `latest`. Its analytics are disabled
   by hook 31 with the Mac's guards: stdin closed (aider otherwise waits for an OpenRouter
   login), `~/.aider/analytics.json` as the marker rather than the exit status, and a
   60-second bound.

Rejected: Homebrew's aider formula (builds numpy and scipy from source, as on the Mac).
