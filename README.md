# setup-dev-linux-wsl

A reproducible, security-minded Ubuntu 26.04 LTS x86_64 development environment,
for WSL2 or plain Linux. It layers apt, vendor apt repos, Homebrew on Linux and
mise, then applies dotfiles with chezmoi. It is the Linux counterpart of the
operator's macOS setup repository and shares its shell conventions and security
invariants.

## Targets

- `--target wsl`: Ubuntu 26.04 LTS in WSL2, systemd on.
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
`--non-interactive` (needs `--git-name NAME --git-email EMAIL`). Run it as your
normal user, never as root. Existing files that chezmoi would change are copied to
`<file>.backup.<UTC timestamp>` first.

## Profiles

| Profile | Default | Purpose |
|---|---|---|
| core | yes | Everyday CLI tools and the shell experience |
| dev | yes | Linters, formatters and scanners |
| security | yes | Security tooling |
| kubernetes | yes | Kubernetes client tooling |
| backup | yes | Backup of non-git state in `$HOME` |
| productivity-extra | no | Optional extra utilities |

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Decisions](docs/DECISIONS.md)
- [Operations](docs/OPERATIONS.md)
- [Tasks](TASKS.md)
- [Agent instructions](AGENTS.md)
