# Operations

Runbook for installing, verifying and recovering the environment.

## Repository tests

```bash
./script/test                       # skips missing linters with a message
REQUIRE_LINTERS=1 ./script/test     # fails instead of skipping; what CI runs
```

Before pushing, run the CI-pinned linters (shellcheck 0.9.0 and shfmt v3.13.1 differ
from the host's):

```bash
docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash -c 'apt-get update -qq && apt-get install -y -qq shellcheck >/dev/null && shellcheck --version && ./script/shell-files | xargs shellcheck -x'
GOBIN="$PWD/.tools/bin" go install mvdan.cc/sh/v3/cmd/shfmt@v3.13.1 && ./script/shell-files | xargs .tools/bin/shfmt -d -i 2 -ci
```

Bash 5 or newer is required. Under an older bash the command stops with
`bash 5 or newer is required`.

## New machine (Linux)

On Ubuntu 26.04 x86_64, as a normal user with sudo:

```bash
git clone <this repository> ~/setup-dev-linux-wsl && cd ~/setup-dev-linux-wsl
./bootstrap plan --target linux      # read it; nothing is changed
./bootstrap apply --target linux     # chezmoi asks the questions listed below
```

On a first interactive run chezmoi asks, in this order: `Git user.name` and
`Git user.email` (skipped when `--git-name` / `--git-email` are given), the commit
signing method (`ssh`, `gpg` or `none`; default `ssh`), the signing key (default
`~/.ssh/id_ed25519.pub`; a GPG key ID for `gpg`), the directory holding work
repositories (default `~/work`) and the git email to use inside it (empty, the
default, disables the work identity). Profiles and shell are not asked: bootstrap
passes them from `--profiles` / `--shell` or their defaults. The answers are recorded
in `~/.config/chezmoi/chezmoi.toml` and never asked again.

The profile list must include `core` (it provides chezmoi, mise and uv); bootstrap
refuses a list without it before any step.

`apply` runs, in order: apt base packages, the removal of `docker.io` and
`podman-docker` (only with `runtime-docker`), signed vendor apt repositories and their
packages, the rest of the Docker setup (only with `runtime-docker`), Homebrew (a pinned
clone, never a downloaded script), the profile packages, chezmoi, then `script/verify`.

### Vendor apt profiles and Docker

Opt in with `--profiles`, for example
`./bootstrap apply --target linux --profiles core,dev,runtime-docker,ai-agents`.

| Profile | Gives you | Targets |
|---|---|---|
| `runtime-docker` | Docker Engine, buildx and compose | linux only |
| `gpu-nvidia` | NVIDIA Container Toolkit | linux only |
| `ai-agents` | Claude Code (`claude-code`) | linux, wsl |
| `cloud-gcp` | `google-cloud-cli` | linux, wsl |
| `cloud-azure` | `azure-cli` and kubelogin | linux, wsl |

`runtime-docker` and `gpu-nvidia` are refused on `--target wsl` until the WSL milestone.

Docker on the linux target, and what to know before using it:

- You are added to the `docker` group, which is root-equivalent: anyone in it can mount
  the host filesystem into a container. It takes effect at your next login; until then
  `docker` needs `sudo`.
- Published ports are reachable from the network (operator decision, ADR-016). UFW does
  not filter them, because Docker writes its own iptables rules. Bind a port to
  `127.0.0.1` in the project's compose file (`127.0.0.1:8080:80`) when it must stay
  local.
- `/etc/docker/daemon.json` is left alone when it is a JSON object whose `log-driver` is
  `local`, so extra keys survive (`sudo nvidia-ctk runtime configure --runtime=docker`
  from the `gpu-nvidia` step adds `runtimes` and is compatible). Any other file is
  replaced with `{"log-driver": "local"}`; the previous one is kept as
  `daemon.json.backup.<UTC timestamp>`, and a running docker is restarted, which stops
  its containers.
- A `docker.sources` that Docker's own instructions wrote is backed up as
  `docker.sources.<UTC timestamp>.bak` in `/etc/apt/sources.list.d/` (APT ignores the
  name) before the managed one replaces it.

Check the vendor sources without changing anything:

```bash
./script/apt-vendor --profiles core,runtime-docker --target linux --check
./script/docker-setup --profiles core,runtime-docker --check
```

Both exit 1 and print each drift (missing or changed keyring or source, a missing
package, an installed conflict, dockerd not enabled or active, you not in the group).
`./script/verify` runs them for the recorded profiles. The keyrings are
`/etc/apt/keyrings/<key>.asc` and the sources `/etc/apt/sources.list.d/<id>.sources`.

If `apt-vendor` stops with "Conflicting APT sources found", another file already
configures that URI with a different `Signed-By` (typically a vendor's own `.list` or
`.sources`). Nothing was written. Remove or rename the file it names, then re-run; the
script never deletes files it did not write. To update a vendor package use
`sudo apt-get update && sudo apt-get upgrade`; the repositories are unpinned (ADR-011).

### After the first apply: two steps you run yourself

The repository never changes your login shell and never uploads a key (ADR-007, ADR-005), so
these stay with you. Do both once per machine.

1. **Make your chosen shell the login shell.** Ubuntu's default login shell is bash,
   and the repository configures only the shell you chose (zsh by default). Until you
   switch, every new terminal, including `wsl -d dev`, opens in bash without Homebrew
   on `PATH`, so `chezmoi`, `mise` and the other tools report "command not found". Do
   not install the snap Ubuntu suggests; start `zsh` for the current session instead.
   `apply` prints the exact `[ACTION]` line; for zsh it is:

   ```bash
   chsh -s /usr/bin/zsh
   ```

   It asks for your Linux password. Open a new terminal and check with `echo $SHELL`.
   For fish, `apply` also prints the line that adds its Homebrew path to
   `/etc/shells`, which `chsh` requires.
2. **Enrol this machine's SSH key** at GitHub, twice (see "Enrol this machine's SSH
   key" below).

## New machine (WSL, run by setup-dev-win)

The Windows repository runs this one inside the distro, so there is no terminal to
answer chezmoi's prompts:

```bash
./bootstrap apply --target wsl --non-interactive \
  --git-name "Your Name" --git-email you@example.com
```

`--non-interactive` requires both identity flags and uses chezmoi's defaults for the
rest. Values must not contain `,`, `=` or `"` (chezmoi's prompt flags cannot carry
them); bootstrap refuses them. A name that needs one of them can be entered at the
interactive prompt instead, or edited into `[data] gitName` afterwards: re-runs never
pass the recorded name back through those flags. Keep checkouts in the Linux filesystem: `script/verify`
fails if it finds git repositories under `/mnt`. The one exception is the Windows host
repository (origin ending in `/setup-dev-win`), which has to live on Windows (ADR-012).

The two steps in "After the first apply" apply here too: run `wsl -d dev`, then
`chsh -s /usr/bin/zsh`, and enrol the SSH key.

## Re-running safely

`./bootstrap apply` is safe to re-run and converges on the same state, but it is not
a no-op, and it never uninstalls anything. Every apply runs `sudo apt-get update` and
installs the base list, which also upgrades a listed package that has a newer
candidate; runs `brew update`, which moves Homebrew itself forward (see ADR-004); and
runs `brew bundle install`, which installs missing formulae and, by default, upgrades
outdated ones. mise installs only runtimes that are missing. Before chezmoi writes, every existing file it would
change is copied to `<file>.backup.<UTC timestamp>`; brand-new files need no backup.
If `~/.config/chezmoi/chezmoi.toml` points at a different source directory it is
backed up too, before `chezmoi init` rewrites it.

Once `~/.config/chezmoi/chezmoi.toml` exists, its `[data]` section is the record of
how this machine was set up, and chezmoi keeps those values whatever flags you pass.
So bootstrap treats it as the source of truth:

- Options you leave out (`--profiles`, `--shell`, `--git-name`, `--git-email`) default
  to the recorded values, and a plain `./bootstrap apply` re-run reproduces the same
  machine.
- An option that disagrees with the record fails before anything runs, naming the
  file and the `[data]` key (`profiles`, `shell`, `gitName`, `gitEmail`). To change
  one, edit that key in the file, then re-run with the new value.

`./bootstrap plan` and `./script/verify` change nothing: they run only the `--check`
forms (the package check renders its Brewfile to a temporary file) and, once chezmoi
is initialised, `chezmoi diff`. `./script/verify` reads profiles and shell from the
same record, so it checks what this machine was set up with, and it fails with a
clear message if chezmoi is not initialised. It reports each check and exits 1 if
any failed. Its chezmoi check ignores scripts, because the SSH hooks run on every
apply by design. The login-shell line is informational.

If `mise install` fails during apply (a network error, an unavailable version), the
runtimes hook exits non-zero, so the apply fails and chezmoi retries the hook on the
next apply; the hooks after it wait for that run. `./script/verify` reports missing
runtimes and names `mise install` as the remedy.

Install, update and recovery procedures beyond this are added as they are built.

## Enrol this machine's SSH key

Every machine has its own SSH key, `~/.ssh/id_ed25519`. `chezmoi apply` generates it
the first time (hook `run_after_12_ssh-key`) and never overwrites, replaces or
copies it. The same key authenticates you to GitHub and signs your commits, and GitHub
treats those as two separate enrolments, so the public key is added **twice**.

1. Print the public key: `cat ~/.ssh/id_ed25519.pub`.
2. Open <https://github.com/settings/ssh/new>, choose **Authentication Key**, paste it
   and save.
3. Open the same page again, choose **Signing Key**, paste the same key and save.
4. Confirm the host key once, by hand: `ssh -T git@github.com`. Compare the fingerprint
   with the list GitHub publishes before answering `yes`. The repository never adds
   GitHub's host keys for you.
5. Switch existing checkouts from https to ssh:
   `git remote set-url origin git@github.com:<owner>/<repo>.git`
6. Check the result: `./script/identity --check`. It verifies the key and its mode, then
   checks commit signing according to `[data] gitSigningMethod` in the chezmoi config:
   for `ssh` it proves signing by creating and verifying a commit in a throwaway
   repository; for `gpg` it asserts `gpg.format = openpgp` and says that gpg signing
   itself is not exercised; for `none` the SSH key is all it requires. If GitHub
   cannot be reached or the key is not yet enrolled it prints a reminder and carries
   on; that step is informational.

Commit signing uses `gpg.format = ssh` with `~/.config/git/allowed_signers`, which the
hook `run_after_13_allowed-signers` writes locally from your public key. It is
not tracked. Both hooks run on every apply, so after replacing or deleting the key,
`chezmoi apply` regenerates the key if missing and rewrites the file when its content differs.

The key has no passphrase, so at rest it is protected only by disk encryption. Add one
with `ssh-keygen -p -f ~/.ssh/id_ed25519`. Neither WSL nor a headless login starts an
ssh-agent by default, so without one you are asked for the passphrase on every use,
including every signed commit. Start one in the shell (`eval "$(ssh-agent -s)"`) and
`AddKeysToAgent yes` adds the key on first use, so you are asked once per agent.

Per-host SSH settings go in `~/.ssh/config.d/`, which the managed config includes first.
Nothing in there is managed or tracked.

### Revoke a lost machine

Because the private key never left that machine, revocation is a single action at the
forge: open <https://github.com/settings/keys>, delete the entries for that machine (its
key appears in both the Authentication and the Signing lists, identified by the
`user@hostname` comment) and, if it held access elsewhere, remove its public key from
those servers' `authorized_keys`. No other machine is affected and nothing needs rotating.
Commits already signed by the revoked key remain in history; verify old ones locally
with `git verify-commit` against an allowed_signers file that still lists the old key.

## LM Studio from WSL: llm-relay

1. On Windows, open LM Studio, load a model and switch the server on (Developer tab:
   status **Running**, `Reachable at: http://127.0.0.1:1234`). Keep "Serve on Local
   Network" off.
2. In a WSL terminal tab: `llm-relay` (or `llm-relay <port>` for another port). It checks
   that LM Studio answers, then relays until you press Ctrl+C.
3. Point tools at `http://127.0.0.1:1234/v1` inside WSL.

`llm-relay --check` sends one request and prints LM Studio's answer, or "Nothing listens on
Windows localhost:1234" when the server is off. Errors from the Windows side are in
`~/.local/state/llm-relay.log`. "port 1234 is already in use" means another `llm-relay`
is running. See ADR-013.

## Quick SSH: conn

`conn` (`~/.local/bin`, the same script as on the Mac) is an fzf picker over the `Host`
aliases in `~/.ssh/config.d/`: `conn` lists them, `conn web` connects straight away when
one alias matches, `conn sftp` or `conn scp` switch mode, and `conn -n` prints the command
instead of running it. `~/.ssh/config.d/` is deliberately not managed by this repository,
so private hostnames never reach it: copy your host files there from the Mac (for example
`scp mac:~/.ssh/config.d/* ~/.ssh/config.d/`). This machine has its own SSH key (see
"Enrol this machine's SSH key"), so add its public key to each server's
`~/.ssh/authorized_keys` before the first `conn`.

## Proxy: proxyon and proxyoff

`proxyon` sets `http_proxy`, `https_proxy`, `all_proxy` and `no_proxy` (and the upper-case
forms) for the current shell; `proxyoff` restores what was there before. The values live
in a private file this repository never manages, `~/.config/proxy/proxy.local.json` (or
the path in `PROXY_SETTINGS`), with exactly these four string keys:

```json
{"http_proxy": "http://proxy.example:3128", "https_proxy": "http://proxy.example:3128",
 "all_proxy": "", "no_proxy": "localhost,127.0.0.1"}
```

`mkdir -p ~/.config/proxy && chmod 700 ~/.config/proxy`, write the file, then
`chmod 600 ~/.config/proxy/proxy.local.json`. An empty string clears that variable. A file
from setup-dev-linux (`~/.config/linux-os-setup/proxy.local.json`) has the same format and
can be moved here. `proxy-settings` explains any rejection (wrong mode, symlink, unknown
key, bad URL). See ADR-014.

## Git shortcuts

The everyday oh-my-zsh git aliases are back under the same names: `g`, `ga`, `gaa`, `gb`,
`gc`, `gcmsg`, `gco`, `gcb`, `gsw`, `gd`, `gds`, `gf`, `gl`, `gp`, `gpf`, `glog`, `grb`,
`grbi`, `gst`, `gsta`, `gstp`. In zsh they are aliases (`alias` lists them); in fish they
are abbreviations that expand as you type.
