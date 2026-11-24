#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RENDER="$ROOT/script/render-brewfile"

# Every entry is a formula with a mandatory purpose comment; nothing else.
mapfile -t entries < <(grep -h -v -E '^[[:space:]]*(#|$)' "$ROOT"/profiles/*.Brewfile)
((${#entries[@]} > 0)) || {
  echo 'No Brewfile entries found' >&2
  exit 1
}
for entry in "${entries[@]}"; do
  [[ "$entry" =~ ^brew\ \"[a-z0-9@+._-]+\"[[:space:]]+#\ .+$ ]] || {
    printf 'Entry lacks formula syntax or purpose comment: %s\n' "$entry" >&2
    exit 1
  }
done
refute_match '^[[:space:]]*(cask|tap|mas|vscode)[[:space:]]' "$ROOT"/profiles
refute_match 'args:' "$ROOT"/profiles

"$RENDER" --output "$TMP/default.Brewfile" >/dev/null
assert_match '^# Generated from reviewed profile fragments\. Do not edit directly\.$' "$TMP/default.Brewfile"
assert_match '^# ---- core\.Brewfile ----$' "$TMP/default.Brewfile"
assert_match '^# ---- shell-zsh\.Brewfile ----$' "$TMP/default.Brewfile"
refute_match '^# ---- shell-fish' "$TMP/default.Brewfile"

"$RENDER" --shell fish --output "$TMP/fish.Brewfile" >/dev/null
assert_match '^# ---- shell-fish\.Brewfile ----$' "$TMP/fish.Brewfile"
refute_match '^# ---- shell-zsh' "$TMP/fish.Brewfile"

# Output parent directory is created when missing.
"$RENDER" --output "$TMP/nested/dir/out.Brewfile" >/dev/null
[[ -s "$TMP/nested/dir/out.Brewfile" ]] || {
  echo 'Output in a missing directory was not created' >&2
  exit 1
}

# One tool per job: the default render stays small and has no duplicates.
count="$(grep -c '^brew "' "$TMP/default.Brewfile")"
((count <= 70)) || {
  printf 'Default render has %s formulae, cap is 70\n' "$count" >&2
  exit 1
}
dupes="$(grep -o '^brew "[^"]*"' "$TMP/default.Brewfile" | sort | uniq -d)"
[[ -z "$dupes" ]] || {
  printf 'Formula declared twice in the default render: %s\n' "$dupes" >&2
  exit 1
}

# Fail closed.
refute_command 'empty profile item accepted' "$RENDER" --profiles core,,dev --output "$TMP/x"
refute_command 'unknown profile accepted' "$RENDER" --profiles nope --output "$TMP/x"
refute_command 'invalid shell accepted' "$RENDER" --shell bash --output "$TMP/x"
refute_command '--output without a value accepted' "$RENDER" --output
[[ ! -e "$TMP/x" ]] || {
  echo 'A rejected render still wrote output' >&2
  exit 1
}

echo 'render-brewfile tests passed.'
