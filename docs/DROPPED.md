# Dropped tools and approaches

Tools and approaches this repository deliberately does not adopt, so the question is
not reopened by accident. One row each. "Origin" says where the idea came from: the
operator's older Linux repository (`setup-dev-linux`, Ansible with SDKMAN, NVM and a
GNOME desktop; its curation reasons are reused where they exist), the macOS repository
(`setup-dev-mac`), or this repository's own design. A row is a decision, not a
prohibition forever: reopening one needs a new ADR.

| Name | What it is | Why dropped | Origin |
|---|---|---|---|
| sdkman | JVM toolchain and SDK manager | mise is the single runtime manager (ADR-003); a second manager for one language family breaks one-tool-per-job (ADR-008). Its installer is also a download-and-run script, which this repository refuses (AGENTS.md). Java, if needed, is a mise tool. | old Linux repo |
| nvm | Node version manager, a shell function sourced at start-up | mise manages Node (ADR-003). nvm slows every shell start and is a second runtime manager. | old Linux repo |
| oh-my-zsh (+ agnoster theme) | zsh framework and prompt theme | Plugin frameworks are third-party code cloned at apply time; the shell is plain zsh with starship, fzf, atuin and a few Homebrew-installed plugins (ADR-007). Starship replaced agnoster. | old Linux repo |
| snap (snapd packages) | Canonical's confined package format | Package layers are apt, Homebrew, mise and uv (ADR-003); snap adds a daemon and a fifth source of binaries, and does not work uniformly in WSL2. The old repo's snap apps were desktop applications (Firefox, Thunderbird, Remmina, Bitwarden), and this repository has no desktop. | old Linux repo |
| GNOME desktop tooling and extensions | dconf settings, gnome-shell extensions, gedit and their manager apps | `--target linux` is headless and `--target wsl` has no GNOME session. Desktop configuration is not workstation baseline here. | old Linux repo |
| ufw / apport roles | Host firewall and crash-report configuration roles | Out of scope: the firewall is the Windows host's or the network's (spec, host firewalls are a mutually exclusive choice and none is configured here), and apport sends crash data to the vendor, which ADR-006 opposes. | old Linux repo |
| httpie | Python HTTP client | `xh` is the single HTTP client (ADR-008). The old repo kept httpie and dropped xh; this repository picks the other way for the same reason: one is enough. | old Linux repo / Mac |
| firejail | SUID-root application sandbox | Hostile or untrusted workloads belong in an isolated VM, not a host sandbox (AGENTS.md, architecture boundary 4); a SUID sandbox widens the host attack surface. | old Linux repo |
| Ansible controller | Ansible and its roles as the provisioning engine | chezmoi is the configuration engine and bootstrap is plain bash (ADR-001 to ADR-004); a second engine would duplicate every decision in two places. | old Linux repo |
| Mandrel / GraalVM via SDKMAN | Native-image JVM distribution and its build dependencies (g++, zlib, libfreetype) | Not part of the baseline. It came with SDKMAN, which is dropped; if native-image builds return, mise provides the JDK and the build dependencies belong to the project's container. | old Linux repo |
| BetterDisplay, iTerm2 and macOS-only casks | macOS GUI applications | There is no macOS here. The Windows half of the workstation is `setup-dev-win`; Linux profiles are Homebrew formulae only, with no casks or taps. | Mac |
| Docker Desktop | Docker's GUI VM product | Docker Engine runs natively in WSL2 or on the host (spec, ADR for the container substrate, milestone 2); Desktop adds a licence, a VM and a socket-sharing path this repository avoids. | Mac / Windows |
| cloud-gcp (deferred, not dropped) | gcloud CLI profile | `gcloud-cli` is a macOS-only cask in homebrew-core, with no Linux formula. It will come from Google's signed apt repository with the vendor-apt machinery (TASKS.md, ADR-010). Same for azure-cli in `cloud-azure`. | Mac |
