# setup-dev-linux-wsl

A reproducible, security-minded Ubuntu 26.04 LTS x86_64 development environment,
for WSL2 or plain Linux. It layers apt, Homebrew on Linux and mise, then applies
dotfiles with chezmoi. Vendor apt repositories (Docker, NVIDIA, Anthropic) arrive in
a later milestone. It is the Linux counterpart of the
operator's macOS setup repository and shares its shell conventions and security
invariants.

## Targets

- `--target wsl`: Ubuntu 26.04 LTS in WSL2. systemd in the distro is configured by
  the Windows repository, setup-dev-win (its milestone 2); this repository neither
  configures nor checks it.
- `--target linux`: Ubuntu 26.04 LTS on bare metal or a VM, headless.

Any other distro, release or architecture is refused before anything changes.

## Quick start

```bash
./bootstrap plan --target wsl    # show what would happen; changes nothing
./bootstrap apply --target wsl   # do it
./script/verify                  # is the machine in the state the repository describes?
./script/test                    # repository tests (bash 5 required)
```

Options: `--target wsl|linux`, `--profiles CSV`, `--shell zsh|fish`,
`--non-interactive` (needs `--git-name NAME --git-email EMAIL`). The profile list
must include `core`. Run it as your normal user, never as root. Existing files that chezmoi would change are copied to
`<file>.backup.<UTC timestamp>` first.

**After the first apply, run two steps yourself** (the repository never does them):

1. Make your chosen shell the login shell: `chsh -s /usr/bin/zsh` (or the line `apply`
   prints for fish). Until then new terminals open in bash without Homebrew on `PATH`,
   and `chezmoi`, `mise` and friends are "not found".
2. Enrol the printed SSH key at GitHub twice, as an authentication key and as a signing
   key.

Details: [docs/OPERATIONS.md](docs/OPERATIONS.md), "After the first apply".

Two commands in `~/.local/bin`: `conn` picks an SSH host from `~/.ssh/config.d/` and
connects; `llm-relay` (WSL) makes LM Studio on Windows reachable at
`http://127.0.0.1:1234/v1` while it runs. Shell helpers: `proxyon`/`proxyoff` (private
proxy file) and the oh-my-zsh git shortcuts (`gst`, `gco`, ...). See OPERATIONS.

## Profiles

| Profile | Default | Purpose |
|---|---|---|
| core | yes | Everyday CLI tools and the shell experience |
| dev | yes | Linters, formatters and scanners |
| security | yes | Security tooling |
| kubernetes | yes | Kubernetes client tooling |
| backup | yes | Backup of non-git state in `$HOME` |
| productivity-extra | no | Optional extra utilities |
| security-scan | no | Host scanners: syft, grype, osv-scanner, trufflehog, dive, cosign, nmap |
| cloud | no | OpenTofu, terraform-docs, terragrunt |
| cloud-aws | no | AWS CLI and Granted SSO sessions |
| cloud-azure | no | kubelogin, and azure-cli from Microsoft's signed apt repository |
| cloud-gcp | no | gcloud (`google-cloud-cli`) from Google's signed apt repository |
| docs | no | d2 and pandoc for diagrams and documents |
| runtime-docker | no | Docker Engine from Docker's signed apt repository (`--target linux` only for now) |
| ai-agents | no | Claude Code from Anthropic's signed apt repository |
| gpu-nvidia | no | NVIDIA Container Toolkit from NVIDIA's signed apt repository (`--target linux` only for now) |
## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Decisions](docs/DECISIONS.md)
- [Dropped tools and approaches](docs/DROPPED.md)
- [Operations](docs/OPERATIONS.md)
- [Tasks](TASKS.md)
- [Agent instructions](AGENTS.md)
