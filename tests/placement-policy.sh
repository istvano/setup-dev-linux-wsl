#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

# Policy greps run over the paths that exist, so the test stays meaningful while
# the tree is still growing. Only the workflows directory is mandatory.
existing_paths() {
  local path
  for path in "$@"; do
    [[ -e "$path" ]] && printf '%s\n' "$path"
  done
  return 0
}

## workflows

WORKFLOWS="$ROOT/.github/workflows"
if [[ ! -d "$WORKFLOWS" ]]; then
  printf 'Missing workflows directory: %s\n' "$WORKFLOWS" >&2
  exit 1
fi

# Every `uses:` is pinned to a full commit SHA.
refute_match 'uses:[[:space:]]+[^#[:space:]]+@(v[0-9]|main|master|latest)' "$WORKFLOWS"
assert_match 'uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}' "$WORKFLOWS"

# Nothing floats.
refute_match '@latest' "$WORKFLOWS"

# Nothing is piped into a shell. tests/ is excluded so this file's own pattern
# and commentary cannot match themselves.
SCAN_PATHS=()
while IFS= read -r path; do
  SCAN_PATHS+=("$path")
done < <(existing_paths "$WORKFLOWS" "$ROOT/script" "$ROOT/bootstrap")
refute_match '(curl|wget)[^|]*\|[[:space:]]*(ba|z)?sh' "${SCAN_PATHS[@]}"

## mise runtimes

MISE_CONFIG="$ROOT/chezmoi/dot_config/mise/config.toml.tmpl"
RUNTIMES_HOOK="$ROOT/chezmoi/run_onchange_after_20_configure-runtimes.sh.tmpl"

# Runtimes are pinned to explicit versions; a floating one changes the toolchain
# under a project without any edit.
refute_match '"latest"' "$MISE_CONFIG"
refute_match '= *"lts"' "$MISE_CONFIG"

# Homebrew lives under /home/linuxbrew; the Apple Silicon prefix must not leak in.
refute_match '/opt/homebrew' "$ROOT/chezmoi"

# The hook provisions the declared runtimes.
assert_match 'mise install' "$RUNTIMES_HOOK"

## shell, prompt and terminal dotfiles (ported from setup-dev-mac)

ZSHRC="$ROOT/chezmoi/dot_zshrc.tmpl"
FISHRC="$ROOT/chezmoi/dot_config/fish/config.fish.tmpl"
LOGIN_HOOK="$ROOT/chezmoi/run_onchange_after_30_report-login-shell.sh.tmpl"
for file in "$ZSHRC" "$FISHRC" "$LOGIN_HOOK" "$ROOT/chezmoi/dot_config/starship.toml" \
  "$ROOT/chezmoi/dot_config/atuin/config.toml" "$ROOT/chezmoi/dot_config/ripgrep/ripgreprc" \
  "$ROOT/chezmoi/dot_tmux.conf" "$ROOT/chezmoi/dot_local/bin/executable_conn"; do
  [[ -f "$file" ]] || {
    printf 'Missing ported dotfile: %s\n' "$file" >&2
    exit 1
  }
done

# macOS-only constructs must not survive the port. Comment lines are filtered out,
# because the files explain what they replaced.
code_lines() { grep -R -h -v -E '^[[:space:]]*#' "$@" || true; }
mac_only="$(code_lines "$ROOT/chezmoi" | grep -E 'UseKeychain|osxkeychain|pinentry-mac|/opt/homebrew|scutil|defaults write|pbcopy' || true)"
[[ -z "$mac_only" ]] || {
  printf 'macOS-only construct under chezmoi/:\n%s\n' "$mac_only" >&2
  exit 1
}

# The login-shell hook only ever tells the operator what to run (AGENTS rule: the
# repository never changes the login shell). No executable chsh line.
chsh_code="$(code_lines "$LOGIN_HOOK" | grep -E '^[[:space:]]*(sudo[[:space:]]+)?chsh' || true)"
[[ -z "$chsh_code" ]] || {
  printf 'login-shell hook executes chsh:\n%s\n' "$chsh_code" >&2
  exit 1
}

# Telemetry opt-out (ADR-046) must be identical in both shells, compared as
# normalised sets: `export X=1` and `set -gx X 1` both become `X=1`. Rendered, so
# the assertion covers what lands in $HOME. The empty-set guard keeps the
# comparison from passing trivially once both files lose the block.
TELEMETRY_RE='HOMEBREW_NO_ANALYTICS|AZURE_CORE_COLLECT_TELEMETRY|CHECKPOINT_DISABLE|DO_NOT_TRACK'
zsh_rendered="$(render linux.toml "$ZSHRC")"
fish_rendered="$(render linux.toml "$FISHRC")"
zsh_telemetry="$(grep -E "^[[:space:]]*export ($TELEMETRY_RE)=" <<<"$zsh_rendered" |
  sed -E 's/^[[:space:]]*export ([A-Z_]+)=(.*)$/\1=\2/' | tr -d "\"'" | sort || true)"
fish_telemetry="$(grep -E "^[[:space:]]*set -gx ($TELEMETRY_RE) " <<<"$fish_rendered" |
  sed -E 's/^[[:space:]]*set -gx ([A-Z_]+) (.*)$/\1=\2/' | tr -d "\"'" | sort || true)"
[[ -n "$zsh_telemetry" ]] || {
  echo 'No telemetry opt-out variables found in the rendered zsh config.' >&2
  exit 1
}
[[ "$(wc -l <<<"$zsh_telemetry" | tr -d ' ')" == 4 ]] || {
  printf 'Expected exactly four telemetry variables in zsh, got:\n%s\n' "$zsh_telemetry" >&2
  exit 1
}
[[ "$zsh_telemetry" == "$fish_telemetry" ]] || {
  printf 'Telemetry opt-out differs between shells.\nzsh:\n%s\nfish:\n%s\n' \
    "$zsh_telemetry" "$fish_telemetry" >&2
  exit 1
}
grep -qx 'HOMEBREW_NO_ANALYTICS=1' <<<"$zsh_telemetry"
grep -qx 'AZURE_CORE_COLLECT_TELEMETRY=false' <<<"$zsh_telemetry"
grep -qx 'CHECKPOINT_DISABLE=1' <<<"$zsh_telemetry"
grep -qx 'DO_NOT_TRACK=1' <<<"$zsh_telemetry"

# fzf and atuin both bind Ctrl-R and the later initialisation wins; atuin is the
# history store, so it must come after fzf in each rendered shell.
init_order() {
  local text="$1" fzf_pat="$2" atuin_pat="$3" label="$4" fzf_line atuin_line
  fzf_line="$(grep -n -- "$fzf_pat" <<<"$text" | head -n 1 | cut -d: -f1 || true)"
  atuin_line="$(grep -n -- "$atuin_pat" <<<"$text" | head -n 1 | cut -d: -f1 || true)"
  [[ -n "$fzf_line" && -n "$atuin_line" ]] || {
    printf '%s: could not locate the fzf and atuin initialisation lines.\n' "$label" >&2
    exit 1
  }
  ((atuin_line > fzf_line)) || {
    printf '%s: atuin (line %s) must initialise after fzf (line %s).\n' \
      "$label" "$atuin_line" "$fzf_line" >&2
    exit 1
  }
}
init_order "$zsh_rendered" 'fzf --zsh' 'atuin init zsh --disable-ai' zshrc
init_order "$fish_rendered" 'fzf --fish' 'atuin init fish --disable-ai' config.fish

# fish_add_path ignores a missing directory, and ~/.local/bin exists only because
# chezmoi creates it for dot_local/bin.
assert_match '^fish_add_path -g [$]HOME/[.]local/bin$' "$FISHRC"
compgen -G "$ROOT/chezmoi/dot_local/bin/*" >/dev/null

# Both shells export the ripgrep config path (rg reads no default location) and
# GPG_TTY, and use plain `bat`: Homebrew installs it as bat, not Debian's batcat.
assert_match 'RIPGREP_CONFIG_PATH' "$ZSHRC" "$FISHRC"
assert_match 'GPG_TTY' "$ZSHRC" "$FISHRC"
refute_match 'batcat' "$ZSHRC" "$FISHRC"
assert_match "alias cat='bat --paging=never'" "$ZSHRC"
assert_match '^auto_sync = false$' "$ROOT/chezmoi/dot_config/atuin/config.toml"

# The runtimes and apps that do not exist on this repository must not leak in.
refute_match 'lmstudio|\.rd/bin|colima|rancher' "$ZSHRC" "$FISHRC"

# The Homebrew prefix has one definition: the brew-shellenv template. The zsh file
# includes it; fish cannot (different syntax) and carries its own guarded line.
assert_match 'template "brew-shellenv"' "$ZSHRC"
assert_match 'test -x /home/linuxbrew/.linuxbrew/bin/brew' "$FISHRC"

# The hook's one instruction, and its silence when already on the selected shell.
# Run it for real: it only prints, so this is safe.
hook_out="$(printf '%s\n' "$(render linux.toml "$LOGIN_HOOK")" | SHELL=/bin/bash bash 2>&1)"
if [[ "$(wc -l <<<"$hook_out" | tr -d ' ')" != 1 ]] || ! grep -q 'chsh -s /usr/bin/zsh' <<<"$hook_out"; then
  printf 'login-shell hook must print exactly one chsh instruction, got:\n%s\n' "$hook_out" >&2
  exit 1
fi
hook_quiet="$(printf '%s\n' "$(render linux.toml "$LOGIN_HOOK")" | SHELL=/usr/bin/zsh bash 2>&1)"
[[ -z "$hook_quiet" ]] || {
  printf 'login-shell hook must be silent when already on zsh, got:\n%s\n' "$hook_quiet" >&2
  exit 1
}

# Syntax: zsh -n on the rendered .zshrc (conn is covered by shell-syntax.sh), and
# fish --no-execute on the rendered fish config. Neither interpreter is installed by
# any profile on the macOS host, so absence skips unless REQUIRE_LINTERS=1.
SYNTAX_TMP="$(mktemp -d)"
trap 'rm -rf "$SYNTAX_TMP"' EXIT
if command -v zsh >/dev/null 2>&1; then
  printf '%s\n' "$zsh_rendered" >"$SYNTAX_TMP/zshrc"
  zsh -n "$SYNTAX_TMP/zshrc"
elif [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
  echo 'zsh is required when REQUIRE_LINTERS=1.' >&2
  exit 1
else
  echo '  zshrc syntax: zsh not installed, skipped'
fi
if command -v fish >/dev/null 2>&1; then
  printf '%s\n' "$fish_rendered" >"$SYNTAX_TMP/config.fish"
  fish --no-execute "$SYNTAX_TMP/config.fish"
elif [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
  echo 'fish is required when REQUIRE_LINTERS=1.' >&2
  exit 1
else
  echo '  config.fish syntax: fish not installed, skipped'
fi

echo 'placement-policy: OK'
