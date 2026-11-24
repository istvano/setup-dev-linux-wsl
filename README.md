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
./script/test                    # repository tests (bash 5 required)
```

`bootstrap` arrives in a later task of the first milestone.

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
