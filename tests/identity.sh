#!/usr/bin/env bash
# script/identity follows the signing method recorded in chezmoi data (R19): ssh gets the
# full check, gpg asserts gpg.format=openpgp and says signing is not exercised, none
# needs only the SSH authentication key. Every case runs under a temporary HOME with its
# own chezmoi config, gitconfig and throwaway key, so the operator's identity is never
# read. A stub `ssh` on PATH makes the informational GitHub check fail fast offline.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
IDENTITY="$ROOT/script/identity"

if ! command -v chezmoi >/dev/null 2>&1; then
  if [[ "${REQUIRE_CHEZMOI:-0}" == 1 ]]; then
    echo 'chezmoi is required when REQUIRE_CHEZMOI=1.' >&2
    exit 1
  fi
  echo 'SKIP: chezmoi not found; script/identity reads the signing method through it'
  exit 0
fi
command -v ssh-keygen >/dev/null 2>&1 || {
  echo 'ssh-keygen is required to test script/identity.' >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "stub ssh: offline" >&2\nexit 255\n' >"$TMP/bin/ssh"
chmod +x "$TMP/bin/ssh"
# One key for every case: generating is the slow part.
ssh-keygen -q -t ed25519 -N '' -C test@identity -f "$TMP/key" >/dev/null

# new_home METHOD [with-key]: a fresh HOME recording METHOD; prints its path.
new_home() {
  local method="$1" home
  home="$(mktemp -d "$TMP/home.XXXXXX")"
  mkdir -p "$home/.config/chezmoi" "$home/.config/git" "$home/.ssh"
  printf '[data]\ngitSigningMethod = "%s"\n' "$method" >"$home/.config/chezmoi/chezmoi.toml"
  if [[ "${2:-}" == with-key ]]; then
    cp "$TMP/key" "$home/.ssh/id_ed25519"
    cp "$TMP/key.pub" "$home/.ssh/id_ed25519.pub"
    chmod 600 "$home/.ssh/id_ed25519"
  fi
  printf '%s\n' "$home"
}
# run_identity HOME: prints combined output; the status is in $rc.
run_identity() {
  rc=0
  out="$(env -u XDG_CONFIG_HOME HOME="$1" GIT_CONFIG_NOSYSTEM=1 PATH="$TMP/bin:$PATH" \
    "$IDENTITY" --check 2>&1)" || rc=$?
}
expect() { # expect DESCRIPTION WANT_RC FRAGMENT
  local description="$1" want="$2" fragment="$3"
  if [[ "$want" == 0 && "$rc" -ne 0 ]] || [[ "$want" != 0 && "$rc" -eq 0 ]]; then
    printf '%s: expected exit %s, got %s:\n%s\n' "$description" "$want" "$rc" "$out" >&2
    exit 1
  fi
  [[ "$out" == *"$fragment"* ]] || {
    printf '%s: expected "%s" in the output:\n%s\n' "$description" "$fragment" "$out" >&2
    exit 1
  }
}

# --- ssh: the full check, including a signed and verified commit.
h="$(new_home ssh with-key)"
printf 'test@example.invalid %s\n' "$(cat "$TMP/key.pub")" >"$h/.config/git/allowed_signers"
cat >"$h/.gitconfig" <<EOF
[user]
  email = test@example.invalid
  signingkey = ~/.ssh/id_ed25519.pub
[gpg]
  format = ssh
[gpg "ssh"]
  allowedSignersFile = $h/.config/git/allowed_signers
EOF
run_identity "$h"
expect 'ssh, fully configured' 0 'A signed commit was created and verified.'

h="$(new_home ssh with-key)"
printf '[gpg]\n  format = openpgp\n' >"$h/.gitconfig"
run_identity "$h"
expect 'ssh method with gpg.format openpgp' 1 'expected ssh'

# --- gpg: the format is asserted; signing itself is not exercised, and says so.
h="$(new_home gpg with-key)"
printf '[gpg]\n  format = openpgp\n' >"$h/.gitconfig"
run_identity "$h"
expect 'gpg, format openpgp' 0 'gpg signing is not exercised by this check'

h="$(new_home gpg with-key)"
printf '[gpg]\n  format = ssh\n' >"$h/.gitconfig"
run_identity "$h"
expect 'gpg method with gpg.format ssh' 1 'expected openpgp'

# --- none: only the SSH authentication key is required.
h="$(new_home none with-key)"
: >"$h/.gitconfig"
run_identity "$h"
expect 'none, key present' 0 'Identity is complete'

h="$(new_home none)"
: >"$h/.gitconfig"
run_identity "$h"
expect 'none, key missing' 1 'No SSH key'

# --- An unknown method or no record at all fails closed.
h="$(new_home rot13 with-key)"
run_identity "$h"
expect 'unknown signing method' 1 'Unknown gitSigningMethod'

h="$(new_home ssh with-key)"
rm -f "$h/.config/chezmoi/chezmoi.toml"
run_identity "$h"
expect 'no chezmoi config' 1 'gitSigningMethod'

echo 'identity tests passed.'
