#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

LOCK="$ROOT/homebrew/brew.lock"
INSTALL="$ROOT/script/install-homebrew"

[[ -f "$LOCK" ]] || {
  echo "missing $LOCK" >&2
  exit 1
}
[[ "$(wc -l <"$LOCK" | tr -d ' ')" == 2 ]] || {
  echo "brew.lock must have exactly two lines" >&2
  exit 1
}
assert_match '^tag=[0-9]+\.[0-9]+\.[0-9]+$' "$LOCK"
assert_match '^commit=[0-9a-f]{40}$' "$LOCK"

[[ -x "$INSTALL" ]] || {
  echo "$INSTALL missing or not executable" >&2
  exit 1
}
assert_match 'merge-base --is-ancestor' "$INSTALL"
assert_match 'rev-parse HEAD' "$INSTALL"
refute_match 'install\.sh' "$INSTALL"
refute_match 'raw\.githubusercontent\.com/Homebrew/install' "$INSTALL"

# Analytics are disabled before the first brew invocation.
export_line="$(grep -n 'export HOMEBREW_NO_ANALYTICS=1' "$INSTALL" | head -1 | cut -d: -f1)"
brew_line="$(grep -nE 'brew ' "$INSTALL" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1)"
[[ -n "$export_line" && -n "$brew_line" ]] || {
  echo "could not locate the analytics export or a brew invocation" >&2
  exit 1
}
((export_line < brew_line)) || {
  echo "HOMEBREW_NO_ANALYTICS is exported after the first brew invocation" >&2
  exit 1
}

# --check must query the stored setting, not the exported variable (which makes
# Homebrew report "disabled" unconditionally).
assert_match 'env -u HOMEBREW_NO_ANALYTICS brew analytics state' "$INSTALL"

# Partial-clone guard: an unrelated repository at the prefix must be refused.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Homebrew"
git -C "$tmp/Homebrew" init -q
git -C "$tmp/Homebrew" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m unrelated
status=0
err="$(BREW_PREFIX="$tmp" "$INSTALL" 2>&1 >/dev/null)" || status=$?
((status != 0)) || {
  echo "install-homebrew accepted an unrelated repository" >&2
  exit 1
}
[[ "$err" == *"partial clone"* ]] || {
  echo "expected 'partial clone' in the error, got: $err" >&2
  exit 1
}

# M12: $USER is unset in bare containers and under some sudo setups, and the script
# runs under set -u. The account comes from id instead.
refute_match '[$][{]?USER([^A-Za-z0-9_]|$)' "$INSTALL" "$ROOT/script/lib" "$ROOT/bootstrap"

# M13: an interrupted first install (clone done, bin/brew symlink not yet made) heals
# on the next run. A copy of the script runs against a local repository whose HEAD is
# the "locked" commit of a copied brew.lock, so the existing-clone path is taken with
# no network and no sudo. Its bin/brew stub answers shellenv, analytics and update.
heal="$tmp/heal"
mkdir -p "$heal/tree/script" "$heal/tree/homebrew" "$heal/prefix/Homebrew/bin"
cp "$INSTALL" "$heal/tree/script/install-homebrew"
cp -R "$ROOT/script/lib" "$heal/tree/script/lib"
printf '#!/bin/sh\nexit 0\n' >"$heal/prefix/Homebrew/bin/brew"
chmod +x "$heal/prefix/Homebrew/bin/brew"
git -C "$heal/prefix/Homebrew" init -q
git -C "$heal/prefix/Homebrew" add bin/brew
git -C "$heal/prefix/Homebrew" -c user.name=t -c user.email=t@example.invalid \
  -c commit.gpgsign=false commit -q -m 'fake brew'
printf 'tag=0.0.0\ncommit=%s\n' "$(git -C "$heal/prefix/Homebrew" rev-parse HEAD)" >"$heal/tree/homebrew/brew.lock"
[[ ! -e "$heal/prefix/bin/brew" ]]
heal_out="$(BREW_PREFIX="$heal/prefix" "$heal/tree/script/install-homebrew" 2>&1)" || {
  printf 'install-homebrew did not heal a missing bin/brew symlink:\n%s\n' "$heal_out" >&2
  exit 1
}
[[ -L "$heal/prefix/bin/brew" && "$(readlink "$heal/prefix/bin/brew")" == ../Homebrew/bin/brew ]] || {
  echo "install-homebrew did not recreate bin/brew -> ../Homebrew/bin/brew" >&2
  exit 1
}

echo "homebrew OK"
