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

# Every `uses:` line is pinned to a full 40-hex commit SHA. Checked line by line, so
# one unpinned action cannot hide behind a pinned one. Comment lines are skipped so
# the explanation of the rule cannot trip it.
uses_lines="$(grep -R -h -E '^[[:space:]]*(-[[:space:]]+)?uses:' "$WORKFLOWS" || true)"
[[ -n "$uses_lines" ]] || {
  echo 'No uses: lines found in the workflows; the pin check would be vacuous.' >&2
  exit 1
}
unpinned="$(grep -v -E 'uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$)' <<<"$uses_lines" || true)"
[[ -z "$unpinned" ]] || {
  printf 'Workflow action not pinned to a 40-hex commit SHA:\n%s\n' "$unpinned" >&2
  exit 1
}

# Nothing floats.
refute_match '@latest' "$WORKFLOWS"

# Nothing is piped into a shell, in any of the usual spellings: `| sh`, `| bash`,
# `| sudo bash`, `bash <(curl ...)`, `sh -c "$(curl ...)"`. tests/ is excluded so this
# file's own patterns cannot match themselves, and comment lines are filtered so the
# files may explain the rule.
SCAN_PATHS=()
while IFS= read -r path; do
  SCAN_PATHS+=("$path")
done < <(existing_paths "$WORKFLOWS" "$ROOT/script" "$ROOT/bootstrap")
scan_code="$(grep -R -h -v -E '^[[:space:]]*#' "${SCAN_PATHS[@]}" || true)"
piped="$(grep -E '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+(-[A-Za-z]+[[:space:]]+)*)?(ba|z|da)?sh([[:space:]]|$)|(ba|z|da)?sh[[:space:]]+(-[a-z]+[[:space:]]+)*<\([[:space:]]*(curl|wget)|(ba|z|da)?sh[[:space:]]+-c[[:space:]]+["'"'"']?[$][(][[:space:]]*(curl|wget)' <<<"$scan_code" || true)"
[[ -z "$piped" ]] || {
  printf 'Download piped into a shell:\n%s\n' "$piped" >&2
  exit 1
}

# The x86_64 integration job: the milestone proof. It runs in the Ubuntu 26.04
# container (the release the provisioner targets) on an x86_64 runner.
VALIDATE="$WORKFLOWS/validate.yml"
assert_match '^  integration:' "$VALIDATE"
assert_match '^    container: ubuntu:26[.]04$' "$VALIDATE"
assert_match '^    runs-on: ubuntu-24[.]04$' "$VALIDATE"
assert_match '^[[:space:]]+sudo[[:space:]]+-u[[:space:]]+dev[[:space:]]+-H' "$VALIDATE"
# Passwordless sudo exists for the CI user only: it may appear under .github/workflows
# and nowhere in what the repository ships or runs.
assert_match 'NOPASSWD' "$WORKFLOWS"
NOPASSWD_PATHS=()
while IFS= read -r path; do
  NOPASSWD_PATHS+=("$path")
done < <(existing_paths "$ROOT/script" "$ROOT/bootstrap" "$ROOT/chezmoi")
refute_match 'NOPASSWD' "${NOPASSWD_PATHS[@]}"
# M45: no checkout leaves the job token in .git/config for later steps to read.
n_checkout="$(grep -c -E '^[[:space:]]*-[[:space:]]+uses:[[:space:]]+actions/checkout@' "$VALIDATE")"
n_persist="$(grep -c -E '^[[:space:]]+persist-credentials:[[:space:]]+false$' "$VALIDATE" || true)"
((n_checkout > 0 && n_checkout == n_persist)) || {
  printf 'Every checkout needs persist-credentials: false (%s checkouts, %s set).\n' "$n_checkout" "$n_persist" >&2
  exit 1
}
# M43: formula availability still runs (and diagnoses) when apply failed.
grep -A1 -E '^[[:space:]]+- name: Formula availability$' "$VALIDATE" |
  grep -qE '^[[:space:]]+if: [$][{][{] !cancelled[(][)] [}][}]$' || {
  echo 'The Formula availability step must run with if: !cancelled().' >&2
  exit 1
}
# #7: the second apply creates no new backups, and a recorded name with a comma
# survives a re-run (F1).
assert_match 'backup' "$VALIDATE"
assert_match 'ci-state/backups' "$VALIDATE"
assert_match 'gitName = \\"CI, Bot\\"' "$VALIDATE"

## mise runtimes

MISE_CONFIG="$ROOT/chezmoi/dot_config/mise/config.toml.tmpl"
RUNTIMES_HOOK="$ROOT/chezmoi/run_onchange_after_20_configure-runtimes.sh.tmpl"

# ADR-011: the latest stable of every component, never an old pin. Every [tools] value
# is "latest", "lts" (node only), "stable" (rust only) or a Java LTS major line; no tool
# carries a hard-coded patch version. Comment lines are excluded.
tool_lines="$(grep -vE '^[[:space:]]*#' "$MISE_CONFIG" | grep -E '^"?[A-Za-z:/_-]+"? *= ')"
while IFS= read -r line; do
  key="${line%%=*}"
  key="${key//[ \"]/}"
  value="${line#*=}"
  value="${value# }"
  case "$key:$value" in
    node:'"lts"' | rust:'"stable"') ;;
    java:'["temurin-21", "temurin-17", "temurin-25"]') ;;
    *:'"latest"') ;;
    *:*)
      echo "mise [tools] entry $key = $value violates ADR-011 (latest/lts/stable/Java LTS only)." >&2
      exit 1
      ;;
  esac
done <<<"$(grep -vE '^(experimental|idiomatic_version_file_enable_tools) ' <<<"$tool_lines")"
refute_match '^[^#]*"[0-9]+[.][0-9]+' "$MISE_CONFIG"
assert_match '^node = "lts"$' "$MISE_CONFIG"
assert_match '^rust = "stable"$' "$MISE_CONFIG"

# codex has no Linux Homebrew formula (ADR-009): it comes through mise's aqua backend
# at "latest" (ADR-011), and must not return to the Brewfile.
assert_match '^"aqua:openai/codex" = "latest"$' "$MISE_CONFIG"
refute_match '^brew "codex"' "$ROOT/profiles"

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

# Telemetry opt-out (ADR-006) must be identical in both shells, compared as
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
# M21: ~/.krew/bin does not exist until krew's first plugin install, so fish must not
# use fish_add_path for it (skipped when missing); it appends unconditionally like zsh.
refute_match 'fish_add_path.*krew' "$FISHRC"
# shellcheck disable=SC2016  # fish's own $HOME and $PATH, matched literally
grep -qxF 'contains -- $HOME/.krew/bin $PATH; or set -gxa PATH $HOME/.krew/bin' <<<"$fish_rendered" || {
  echo 'config.fish (kubernetes profile) does not append ~/.krew/bin unconditionally.' >&2
  exit 1
}
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

# The login-shell hook, run for real (it only prints). Login shell is stubbed through
# LOGIN_SHELL_OVERRIDE. zsh: one chsh line when on bash, silent when already on zsh.
run_hook() { # run_hook FIXTURE LOGIN_SHELL
  printf '%s\n' "$(render "$1" "$LOGIN_HOOK")" | LOGIN_SHELL_OVERRIDE="$2" bash 2>&1
}
hook_out="$(run_hook linux.toml /bin/bash)"
if [[ "$(wc -l <<<"$hook_out" | tr -d ' ')" != 1 ]] || ! grep -q 'chsh -s /usr/bin/zsh' <<<"$hook_out"; then
  printf 'login-shell hook must print exactly one chsh instruction for zsh, got:\n%s\n' "$hook_out" >&2
  exit 1
fi
hook_quiet="$(run_hook linux.toml /usr/bin/zsh)"
[[ -z "$hook_quiet" ]] || {
  printf 'login-shell hook must be silent when already on zsh, got:\n%s\n' "$hook_quiet" >&2
  exit 1
}
# fish (Homebrew path, not in /etc/shells): the /etc/shells line then chsh, both printed.
# A stub fish on PATH stands in for the Homebrew binary.
FAKEBIN="$(mktemp -d)"
printf '#!/bin/sh\n' >"$FAKEBIN/fish"
chmod +x "$FAKEBIN/fish"
fish_fixture="$FAKEBIN/fish.toml"
sed 's/^shell = .*/shell = "fish"/' "$ROOT/tests/fixtures/chezmoi/linux.toml" >"$fish_fixture"
fish_hook_out="$(printf '%s\n' "$(render "$fish_fixture" "$LOGIN_HOOK")" |
  PATH="$FAKEBIN:$PATH" LOGIN_SHELL_OVERRIDE=/bin/bash bash 2>&1)"
if ! grep -qF "echo $FAKEBIN/fish | sudo tee -a /etc/shells" <<<"$fish_hook_out" ||
  ! grep -qF "chsh -s $FAKEBIN/fish" <<<"$fish_hook_out"; then
  printf 'fish hook output lacks the /etc/shells and chsh instructions:\n%s\n' "$fish_hook_out" >&2
  exit 1
fi
rm -rf "$FAKEBIN"

# conn --help is extracted by fixed line numbers (sed -n '2,8p'), so the provenance
# header must not shift it: the help must equal the Mac's.
conn_help="$(zsh "$ROOT/chezmoi/dot_local/bin/executable_conn" --help 2>&1 || true)"
if command -v zsh >/dev/null 2>&1; then
  if ! grep -q '^conn — fzf picker' <<<"$conn_help" ||
    ! grep -q '^-n prints the command instead of running it\.' <<<"$conn_help" ||
    grep -q 'Provenance' <<<"$conn_help"; then
    printf 'conn --help output is wrong:\n%s\n' "$conn_help" >&2
    exit 1
  fi
fi

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

## git, ssh and per-machine signing identity

KEY_HOOK="$ROOT/chezmoi/run_after_12_ssh-key.sh.tmpl"
SIGNERS_HOOK="$ROOT/chezmoi/run_after_13_allowed-signers.sh.tmpl"
for file in "$KEY_HOOK" "$SIGNERS_HOOK" "$ROOT/script/identity"; do
  [[ -f "$file" ]] || {
    printf 'Missing identity file: %s\n' "$file" >&2
    exit 1
  }
done
# These hooks must be run_after_, not run_onchange_. chezmoi re-runs a run_onchange_
# script only when its rendered text changes, so a deleted key, a replaced key or a
# failed first generation would never be repaired by a later apply.
[[ "$(basename "$KEY_HOOK")" == run_after_* && "$(basename "$SIGNERS_HOOK")" == run_after_* ]] || {
  echo 'identity hooks must be run_after_, not run_onchange_.' >&2
  exit 1
}
# The key hook guards generation behind an existing-key check and never removes or
# regenerates a key in place: no rm, no -y (re-derive), no overwrite-by-force.
assert_match '\[\[ -f ' "$KEY_HOOK"
keygen_line="$(grep -n 'ssh-keygen -t' "$KEY_HOOK" | head -1 | cut -d: -f1)"
guard_line="$(grep -n '\[\[ -f ' "$KEY_HOOK" | head -1 | cut -d: -f1)"
[[ -n "$keygen_line" && -n "$guard_line" && "$guard_line" -lt "$keygen_line" ]] || {
  echo 'ssh-key hook: the [[ -f guard must precede ssh-keygen.' >&2
  exit 1
}
key_code="$(code_lines "$KEY_HOOK")"
! grep -qE '(^|[[:space:]])rm[[:space:]]|ssh-keygen[^|]*[[:space:]]-y([[:space:]]|$)|y\|yes' <<<"$key_code" || {
  echo 'ssh-key hook removes or re-derives a key.' >&2
  exit 1
}
# The allowed_signers hook publishes through a temp file and an atomic mv.
signers_code="$(code_lines "$SIGNERS_HOOK")"
grep -q 'mktemp' <<<"$signers_code" || {
  echo 'allowed-signers hook must write via mktemp.' >&2
  exit 1
}
grep -qE 'cmp -s' <<<"$signers_code" || {
  echo 'allowed-signers hook must compare before replacing.' >&2
  exit 1
}
grep -qE '^[[:space:]]*mv ' <<<"$signers_code" || {
  echo 'allowed-signers hook must publish with mv.' >&2
  exit 1
}
# The ssh config never delegates to a macOS agent or keychain, and never forwards.
ssh_cfg="$ROOT/chezmoi/private_dot_ssh/config.tmpl"
refute_match '^[[:space:]]*(IdentityAgent|UseKeychain)' "$ssh_cfg"
refute_match '^[[:space:]]*ForwardAgent[[:space:]]+yes' "$ssh_cfg"

## krew plugins, opt-in profiles, DROPPED.md, apt base additions (ADR-010)

KREW_HOOK="$ROOT/chezmoi/run_onchange_after_28_krew-plugins.sh.tmpl"
[[ -f "$KREW_HOOK" ]] || {
  echo 'Missing chezmoi/run_onchange_after_28_krew-plugins.sh.tmpl.' >&2
  exit 1
}
# Gated on the kubernetes profile, the plugin list declared once and exactly these five,
# the Homebrew environment from the single template, and ~/.krew/bin created first.
assert_match '^\{\{-? if has "kubernetes" \.profiles -?\}\}' "$KREW_HOOK"
assert_match '\{\{ template "brew-shellenv" \. \}\}' "$KREW_HOOK"
# shellcheck disable=SC2016  # a Go-template variable, matched literally
krew_list="$(grep -E '^\{\{-?[[:space:]]*\$plugins := list ' "$KREW_HOOK" | head -n 1 || true)"
[[ "$(grep -oE '"[^"]+"' <<<"$krew_list" | tr -d '"' | sort | paste -sd, -)" == 'images,neat,tree,view-secret,whoami' ]] || {
  printf 'krew hook must declare exactly neat view-secret tree whoami images; got: %s\n' "$krew_list" >&2
  exit 1
}
# shellcheck disable=SC2016  # the hook's own $HOME, matched literally
mkdir_line="$(grep -n 'mkdir -p "\$HOME/.krew/bin"' "$KREW_HOOK" | head -n 1 | cut -d: -f1 || true)"
install_line="$(grep -n 'krew install' "$KREW_HOOK" | grep -v '^[0-9]*:[[:space:]]*#' | head -n 1 | cut -d: -f1 || true)"
if [[ -z "$mkdir_line" || -z "$install_line" ]] || ((mkdir_line >= install_line)); then
  echo 'krew hook must mkdir -p ~/.krew/bin before the first install.' >&2
  exit 1
fi
# The shells' comments must be true: the hook they name exists (fish used to claim
# nothing creates the directory).
assert_match 'run_onchange_after_28_krew-plugins' "$ROOT/chezmoi/dot_config/fish/config.fish.tmpl"
refute_match 'nothing creates ~/.krew/bin' "$ROOT/chezmoi/dot_config/fish/config.fish.tmpl"

# The new profiles are opt-in: valid, with a fragment, and not in the default.
# shellcheck source=script/lib/profiles.sh
source "$ROOT/script/lib/profiles.sh"
for optin in security-scan cloud cloud-aws cloud-azure docs; do
  [[ ",$DEFAULT_PROFILES," != *",$optin,"* ]] || {
    printf 'profile %s must be opt-in but is in DEFAULT_PROFILES.\n' "$optin" >&2
    exit 1
  }
  [[ -s "$ROOT/profiles/$optin.Brewfile" ]] || {
    printf 'missing profile fragment: %s\n' "$optin" >&2
    exit 1
  }
  assert_match "^\\| $optin \\| no \\|" "$ROOT/README.md"
done
for must in syft grype osv-scanner trufflehog cosign nmap; do
  assert_match "^brew \"$must\"" "$ROOT/profiles/security-scan.Brewfile"
done
for must in opentofu terraform-docs terragrunt; do
  assert_match "^brew \"$must\"" "$ROOT/profiles/cloud.Brewfile"
done
assert_match '^brew "awscli"' "$ROOT/profiles/cloud-aws.Brewfile"
assert_match '^brew "kubelogin"' "$ROOT/profiles/cloud-azure.Brewfile"
assert_match '^brew "d2"' "$ROOT/profiles/docs.Brewfile"
assert_match '^brew "pandoc"' "$ROOT/profiles/docs.Brewfile"
# gcloud and azure-cli are macOS-only casks in homebrew-core: they must not appear as
# formulae, and cloud-gcp must not exist until the vendor apt machinery does.
refute_match '^brew "(azure-cli|gcloud-cli|google-cloud-sdk)"' "$ROOT/profiles"
[[ ! -e "$ROOT/profiles/cloud-gcp.Brewfile" ]] || {
  echo 'cloud-gcp.Brewfile exists but is deferred to the vendor-apt milestone.' >&2
  exit 1
}
assert_match 'cloud-gcp' "$ROOT/TASKS.md"
assert_match 'azure-cli' "$ROOT/TASKS.md"

# docs/DROPPED.md: one row per dropped tool, linked from the README and ARCHITECTURE.
DROPPED="$ROOT/docs/DROPPED.md"
[[ -s "$DROPPED" ]] || {
  echo 'Missing docs/DROPPED.md.' >&2
  exit 1
}
for name in sdkman nvm oh-my-zsh snap GNOME ufw apport httpie firejail Ansible Mandrel BetterDisplay iTerm2 'Docker Desktop' cloud-gcp; do
  assert_match "^\\|[^|]*$name" "$DROPPED"
done
assert_match 'docs/DROPPED\.md' "$ROOT/README.md"
assert_match 'DROPPED\.md' "$ROOT/docs/ARCHITECTURE.md"

# apt base: wget and libxml2-utils, each with a purpose comment (ADR-010).
assert_match '^wget[[:space:]]+# .+' "$ROOT/apt/base.list"
assert_match '^libxml2-utils[[:space:]]+# .+' "$ROOT/apt/base.list"

# CI's formula-availability step covers every opt-in profile.
for optin in security-scan cloud cloud-aws cloud-azure docs; do
  assert_match "--profiles core,dev,security,kubernetes,backup,productivity-extra,.*$optin" "$ROOT/.github/workflows/validate.yml"
done

echo 'placement-policy: OK'
