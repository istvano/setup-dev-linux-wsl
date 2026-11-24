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

echo "homebrew OK"
