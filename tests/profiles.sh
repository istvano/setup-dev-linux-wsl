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

# The chezmoi template carries a second copy of the list; it must match exactly
# (same set, same count) and its default must equal DEFAULT_PROFILES.
tmpl="$ROOT/chezmoi/.chezmoi.toml.tmpl"
[[ -f "$tmpl" ]] || fail 'chezmoi/.chezmoi.toml.tmpl is missing'
choices_line="$(grep -E '[$]profileChoices := list ' "$tmpl")" ||
  fail "No profileChoices list in .chezmoi.toml.tmpl"
tmpl_profiles=()
while IFS= read -r p; do tmpl_profiles+=("$p"); done < <(grep -oE '"[^"]+"' <<<"$choices_line" | tr -d '"')
((${#tmpl_profiles[@]} == ${#VALID_PROFILES[@]})) ||
  fail "chezmoi profile choices (${#tmpl_profiles[@]}) differ in count from VALID_PROFILES (${#VALID_PROFILES[@]})"
for profile in "${VALID_PROFILES[@]}"; do
  found=false
  for t in "${tmpl_profiles[@]}"; do [[ "$t" == "$profile" ]] && found=true; done
  [[ "$found" == true ]] || fail "chezmoi profile choices lack: $profile"
done
default_line="$(grep -E 'promptMultichoiceOnce . "profiles"' "$tmpl")" ||
  fail 'No profiles prompt in .chezmoi.toml.tmpl'
tmpl_default="$(grep -oE '\(list [^)]*\)' <<<"$default_line" | grep -oE '"[^"]+"' | tr -d '"' | paste -sd, -)"
[[ "$tmpl_default" == "$DEFAULT_PROFILES" ]] ||
  fail "chezmoi default profiles '$tmpl_default' != DEFAULT_PROFILES '$DEFAULT_PROFILES'"

# README table: a row naming each valid profile.
for profile in "${VALID_PROFILES[@]}"; do
  assert_match "^\\| $profile \\|" "$ROOT/README.md"
done

echo 'profile catalogue tests passed.'
