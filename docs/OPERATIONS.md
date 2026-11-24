# Operations

Runbook for installing, verifying and recovering the environment.

## Repository tests

```bash
./script/test                       # skips missing linters with a message
REQUIRE_LINTERS=1 ./script/test     # fails instead of skipping; what CI runs
```

Bash 5 or newer is required. Under an older bash the command stops with
`bash 5 or newer is required`.

Install, update and recovery procedures are added as `bootstrap` is built.

## Enrol this machine's SSH key

Every machine has its own SSH key, `~/.ssh/id_ed25519`. `chezmoi apply` generates it
the first time (hook `run_onchange_after_12_ssh-key`) and never overwrites, replaces or
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
hook `run_onchange_after_13_allowed-signers` writes locally from your public key. It is
not tracked. After replacing the key, delete that file and run `chezmoi apply`.

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
