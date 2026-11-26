# Tasks

Unfinished work only. Milestone 1 (skeleton, bootstrap, apt base, Homebrew, the
default profiles, mise, chezmoi dotfiles, identity, verify, CI) is built; what it
deferred is listed under "Milestone 1 follow-ups". Later milestones follow the spec's
phasing (section 9).

## Milestone 2

- [ ] L3: WSL integration, Docker Engine, the container substrate and exposure
      checks. Done when `docker compose` works and nothing listens beyond loopback.
      The change that sets `appendWindowsPath=false` must ship the `~/.local/bin/code`
      wrapper (VS Code's WSL launcher) in the same patch: the gitconfig difftool and
      mergetool and the editor fallback find `code` through the Windows PATH today, and
      would silently stop working. (The nvim clipboard bridge, ADR-015, already prefers
      absolute /mnt/c/Windows/System32 paths, so it is not affected.)
- [ ] Vendor apt repositories with committed keys and `apt/pins.lock` (spec L1, not
      built in milestone 1). Each lands with the milestone that first needs it:
      Docker here, NVIDIA in L4, Anthropic in L5.

## Milestone 3

- [ ] L4: `gpu-nvidia` profile and `gpu-check`. Done when an eGPU present and absent
      are both handled.

## Milestone 4

- [ ] L5: AI agents and policy, including the `mcp/` catalogue. Done when the agents
      run with policy applied.

## Milestone 5

- [ ] L6: `update-report` and `test-install`. Done when a throwaway distro install
      passes.
- [ ] W7 (both repositories): the LM Studio bridge, `local-llm` profile (spec 8.2).

## Milestone 1 follow-ups

- [ ] Align host and CI linter versions. shfmt is pinned v3.13.1 in CI but floats with
      Homebrew on the host; shellcheck is apt 0.9.0 in CI against 0.11.0 on the host
      (SC2015 passed locally and failed in CI). Options: pin shellcheck in CI from its
      release with a sha256, as chezmoi is pinned, and/or pin the host's linters via mise.

Security and correctness:

- [ ] Refresh `homebrew/brew.lock` when Homebrew releases (ADR-011). It only anchors
      the verified first clone; `brew update` follows, so nothing installed is stale.
- [ ] Verify codex's SHA-256: the aqua registry entry declares no checksum, so the
      archive is trusted on GitHub TLS alone (ADR-009). A mise lockfile with
      checksums is one way.
- [ ] Spec 7.3 preflight "ext4 home" is not implemented.
- [ ] `repos_under_mnt` (depth 4) misses common Windows layouts and walks
      `C:\Windows` over 9P; scope it to user directories.
- [ ] CI pins chezmoi 2.72.0 while machines run Homebrew's current chezmoi; align or
      test both.
- [ ] M13 remainder: a clone interrupted between `git clone` and the exact-commit
      check is accepted later if its HEAD descends from the pin.
- [ ] `gpg.program` in the gitconfig still comes from `lookPath "gpg"`, so its
      rendering depends on the caller's PATH (the class of F5).
- [ ] `script/identity` does not exercise gpg signing (R19); only the format is
      asserted.
- [ ] M36: a foreign chezmoi config without the four data keys dies before
      `backup_foreign_config`, and the message says to remove it without a backup.
- [ ] M27: `script/identity` signs with `-c` overrides instead of the real gitconfig.
- [ ] M30: the GitHub probe in `script/identity` has no ServerAlive bound.
- [ ] M31: the gitconfig credential-helper comment overstates its guarantee.
- [ ] M3: `atomic_write` drops the target's mode and leaves its RETURN trap set.
- [ ] M4: `backup_file` has one-second granularity; two backups in a second collide.
- [ ] M9: an os-release file that exits non-zero aborts `require_supported_ubuntu`
      under `set -e` without the die message.
- [ ] M11: `detect_target` does not save and restore `nocasematch`.
- [ ] M28: `core.editor` falls back to nano while the shells prefer nvim > vim > code.
- [ ] M40: verify's message when chezmoi is missing from PATH is unclear.

Tests and CI:

- [ ] M1: the file selector's exit status is swallowed by process substitution in
      `tests/shell-syntax.sh` and `tests/format.sh`.
- [ ] M5: no tests for the `common.sh` helpers (confirm, backup_file, atomic_write).
- [ ] M10: no test for a missing os-release file or the `repos_under_mnt` depth
      boundary.
- [ ] M14: the analytics-order test reads text and misses `activate_homebrew`.
- [ ] M15: the partial-clone test commit inherits `commit.gpgsign`.
- [ ] M16: no test that install-homebrew accepts a descendant of the locked commit.
- [ ] M17: `script/packages`' install path is only source-grepped; run it on a stub.
- [ ] M18: the mise "latest"/"lts" refutes are comment-sensitive and miss
      single-quoted and `lts/*` forms.
- [ ] M19: the wsl branch of target detection is not exercised (fake osrelease).
- [ ] M20: no regression asserts for autoCommit/autoPush=false, the gpg|none choices
      and ephemeral.
- [ ] M23: the atuin-after-fzf order check does not skip comments.
- [ ] M24: the fish Homebrew prefix literal is not tied to the brew-shellenv template.
- [ ] M25: regex nits (rancher case, other telemetry assignment forms, chsh refute
      only at line start).
- [ ] M26: the FAKEBIN temp dir in `tests/placement-policy.sh` leaks on failure.
- [ ] M29: the `y\|yes` refute regex is literal under ERE.
- [ ] M33: no behavioural test of bootstrap's backup path (stub `chezmoi status`).
- [ ] M38: `conflict_case`'s temp file in `tests/bootstrap.sh` leaks on failure.
- [ ] M41: CI's re-clone detection by `.git` inode is weak; use a sentinel file.
- [ ] M42: CI's `chezmoi diff` scope hides non-deterministic run_onchange_ re-runs.
- [ ] M43 remainder: the formula-availability step hardcodes the profile list.
- [ ] M44: the CI backup check should grep `name = seed` in the backup.
- [ ] M46: more curl-pipe spellings to refute (`| /bin/bash`, `sudo -u root bash`,
      `$(curl|sh)`, `source <(curl)`).
- [ ] M47: the M7 strictness comment in `tests/placement-policy.sh`.
