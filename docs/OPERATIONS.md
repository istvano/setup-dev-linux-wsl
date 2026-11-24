# Operations

Runbook for installing, verifying and recovering the environment.

## Repository tests

```bash
./script/test                       # skips missing linters with a message
REQUIRE_LINTERS=1 ./script/test     # fails instead of skipping; what CI runs
```

Bash 5 or newer is required. Under an older bash the command stops with
`bash 5 or newer is required`.

## New machine (Linux)

On Ubuntu 26.04 x86_64, as a normal user with sudo:

```bash
git clone <this repository> ~/setup-dev-linux-wsl && cd ~/setup-dev-linux-wsl
./bootstrap plan --target linux      # read it; nothing is changed
./bootstrap apply --target linux     # chezmoi asks for your git name and email
```

`apply` runs, in order: apt base packages, Homebrew (a pinned clone, never a
downloaded script), the profile packages, chezmoi, then `script/verify`. Enrol the
SSH key it prints (see the section below) and, if you want the new shell as your
login shell, run the `chsh` line it reports; the repository never does either.

## New machine (WSL, run by setup-dev-win)

The Windows repository runs this one inside the distro, so there is no terminal to
answer chezmoi's prompts:

```bash
./bootstrap apply --target wsl --non-interactive \
  --git-name "Your Name" --git-email you@example.com
```

`--non-interactive` requires both identity flags and uses chezmoi's defaults for the
rest. Values must not contain `,` or `=` (chezmoi's prompt flags cannot carry them);
bootstrap refuses them. Keep checkouts in the Linux filesystem: `script/verify`
fails if it finds git repositories under `/mnt`.

## Re-running safely

`./bootstrap apply` is idempotent: apt and Homebrew skip what is installed, and
nothing is ever uninstalled. Before chezmoi writes, every existing file it would
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
6. Check the result: `./script/identity --check`. It verifies the key and its mode, and
   proves signing by creating and verifying a commit in a throwaway repository. If GitHub
   cannot be reached or the key is not yet enrolled it prints a reminder and carries on;
   that step is informational.

Commit signing uses `gpg.format = ssh` with `~/.config/git/allowed_signers`, which the
hook `run_after_13_allowed-signers` writes locally from your public key. It is
not tracked. Both hooks run on every apply, so after replacing or deleting the key,
`chezmoi apply` regenerates the key if missing and rewrites the file when its content differs.

The key has no passphrase, so at rest it is protected only by disk encryption. Add one
with `ssh-keygen -p -f ~/.ssh/id_ed25519`; `AddKeysToAgent yes` means you are then asked
once per agent session.

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
