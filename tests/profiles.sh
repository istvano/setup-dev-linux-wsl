#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=script/lib/common.sh
source "$ROOT/script/lib/common.sh"
# shellcheck source=script/lib/profiles.sh
source "$ROOT/script/lib/profiles.sh"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

# Every valid profile has a fragment, and every fragment (bar shell-*) is valid.
for profile in "${VALID_PROFILES[@]}"; do
  [[ -f "$ROOT/profiles/$profile.Brewfile" ]] || fail "Missing fragment for profile: $profile"
done
for file in "$ROOT"/profiles/*.Brewfile; do
  name="$(basename "$file" .Brewfile)"
  [[ "$name" == shell-* ]] && continue
  found=false
  for profile in "${VALID_PROFILES[@]}"; do
    [[ "$profile" == "$name" ]] && found=true
  done
  [[ "$found" == true ]] || fail "Fragment without a profile: $name"
done

# Defaults are valid profiles.
validate_profiles "$DEFAULT_PROFILES"

# The chezmoi template carries a second copy of the list; Task 9 adds it.
tmpl="$ROOT/chezmoi/.chezmoi.toml.tmpl"
if [[ -f "$tmpl" ]]; then
  assert_match 'choice' "$tmpl"
  for profile in "${VALID_PROFILES[@]}"; do
    assert_match "\"$profile\"" "$tmpl"
  done
else
  echo 'SKIP: chezmoi/.chezmoi.toml.tmpl not present yet (Task 9)'
fi

# README table: a row naming each valid profile.
for profile in "${VALID_PROFILES[@]}"; do
  assert_match "^\\| $profile \\|" "$ROOT/README.md"
done

echo 'profile catalogue tests passed.'
