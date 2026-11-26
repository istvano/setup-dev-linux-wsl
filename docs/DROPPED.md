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
| oh-my-zsh (+ agnoster theme) | zsh framework and prompt theme | Plugin frameworks are third-party code cloned at apply time and a second source of shell behaviour; the shell is plain zsh with starship, fzf, atuin and Homebrew-installed plugins. Starship replaced agnoster. Its everyday git aliases are kept as plain aliases and fish abbreviations (ADR-014). Design decision, no ADR. | old Linux repo |
| snap (snapd packages) | Canonical's confined package format | Package layers are apt, Homebrew, mise and uv (ADR-003); snap adds a daemon and another source of binaries. The old repo's snap apps were desktop applications (Firefox, Thunderbird, Remmina, Bitwarden), and this repository has no desktop. | old Linux repo |
| GNOME desktop tooling and extensions | dconf settings, gnome-shell extensions, gedit and their manager apps | `--target linux` is headless and `--target wsl` has no GNOME session. Desktop configuration is not workstation baseline here. | old Linux repo |
| ufw / apport roles | Host firewall and crash-report configuration roles | The outbound firewall belongs to the Windows host (design spec, execution-boundary table: Windows host owns the firewall); this repository configures none. apport sends crash reports to the vendor, against the no-vendor-reporting rule in AGENTS.md (the telemetry opt-outs of ADR-006 are the related decision). Design decision, no ADR. | old Linux repo |
| httpie | Python HTTP client | `xh` is the single HTTP client (ADR-008). The old repo kept httpie and dropped xh; this repository picks the other way for the same reason: one is enough. | old Linux repo / Mac |
| firejail | SUID-root application sandbox | Hostile or untrusted workloads belong in an isolated VM, not a host sandbox (AGENTS.md, architecture boundary 4); a SUID sandbox widens the host attack surface. | old Linux repo |
| Ansible controller | Ansible and its roles as the provisioning engine | chezmoi is the configuration engine (AGENTS.md) and bootstrap is plain bash with a pinned Homebrew clone (ADR-004); a second engine would duplicate every decision in two places. The design spec also keeps the old Ansible repository separate. Design decision, no ADR. | old Linux repo |
| Mandrel / GraalVM via SDKMAN | Native-image JVM distribution and its build dependencies (g++, zlib, libfreetype) | Not part of the baseline. It came with SDKMAN, which is dropped; if native-image builds return, mise provides the JDK and the build dependencies belong to the project's container. | old Linux repo |
| BetterDisplay, iTerm2 and macOS-only casks | macOS GUI applications | There is no macOS here. The Windows half of the workstation is `setup-dev-win`; Linux profiles are Homebrew formulae only, with no casks or taps. | Mac |
| Docker Desktop | Docker's GUI VM product | Docker Engine in WSL2 replaces it (design spec); Desktop adds a licence, a VM and a socket-sharing path this repository avoids. The Engine work is milestone 2 in TASKS.md and has no ADR yet. | Mac / Windows |
| cloud-gcp (deferred, not dropped) | gcloud CLI profile | `gcloud-cli` is a macOS-only cask in homebrew-core, with no Linux formula. It will come from Google's signed apt repository with the vendor-apt machinery (TASKS.md, ADR-010). Same for azure-cli in `cloud-azure`. | Mac |
