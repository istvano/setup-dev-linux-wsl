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

# script/packages renders with the caller's selection and never removes anything.
PACKAGES="$ROOT/script/packages"
assert_match '^[[:space:]]*--profiles \| --shell\)' "$PACKAGES"
assert_match 'script/render-brewfile" .*render_args' "$PACKAGES"
assert_match 'brew bundle check' "$PACKAGES"
assert_match 'brew bundle install' "$PACKAGES"
refute_match 'brew bundle (cleanup|dump)' "$PACKAGES"
assert_match 'default_brewfile_path' "$RENDER"
assert_match 'default_brewfile_path' "$PACKAGES"
refute_command 'packages: --profiles without a value accepted' "$PACKAGES" --profiles
refute_command 'packages: unknown option accepted' "$PACKAGES" --nope

# Behaviour with a stub brew: the selection reaches the rendered file and brew is
# asked to check/install exactly that file.
STUB="$TMP/prefix"
mkdir -p "$STUB/bin"
cat >"$STUB/bin/brew" <<'STUBEOF'
#!/usr/bin/env bash
# A real brew's shellenv puts its own bin first; the stub must do the same.
if [[ "${1-}" == shellenv ]]; then
  printf 'export PATH="%s:$PATH"\n' "$(dirname "${BASH_SOURCE[0]}")"
  exit 0
fi
printf '%s\n' "$*" >>"$BREW_LOG"
# Keep a copy of the Brewfile brew was asked about: --check renders a temp file that
# is gone by the time the script returns.
if [[ "${1-}" == bundle && "${2-}" == check ]]; then cp "$4" "$BREW_LOG.file"; fi
STUBEOF
chmod +x "$STUB/bin/brew"
export BREW_LOG="$TMP/brew.log"
BREW_PREFIX="$STUB" XDG_CONFIG_HOME="$TMP/xdg" "$PACKAGES" --check --profiles core --shell fish >/dev/null
# R17: --check writes nothing at the default Brewfile path (nor its directory).
[[ ! -e "$TMP/xdg/setup-dev-linux-wsl/Brewfile" ]] || {
  echo "packages --check wrote the default Brewfile" >&2
  exit 1
}
[[ ! -e "$TMP/xdg" ]] || {
  echo "packages --check created the config directory" >&2
  exit 1
}
assert_match '^# Profiles: core$' "$BREW_LOG.file"
assert_match '^# ---- shell-fish\.Brewfile ----$' "$BREW_LOG.file"
assert_match "^bundle check --file /.* --verbose$" "$BREW_LOG"
refute_match "xdg" "$BREW_LOG"
refute_command 'packages: missing Homebrew accepted' env BREW_PREFIX="$TMP/none" "$PACKAGES" --check

echo 'render-brewfile tests passed.'
