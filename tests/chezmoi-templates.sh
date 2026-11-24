#!/usr/bin/env bash
# Validate the chezmoi templates.
#
# .chezmoiroot points chezmoi at <repo>/chezmoi, so .chezmoi.sourceDir is the
# chezmoi subdirectory, not the repository root. Repository paths must go
# through `dir .chezmoi.sourceDir`.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

TEMPLATES=()
while IFS= read -r found; do TEMPLATES+=("$found"); done \
  < <(find "$ROOT/chezmoi" -type f -name '*.tmpl' | sort)
((${#TEMPLATES[@]} > 0)) || {
  echo 'No chezmoi templates discovered; the selector is broken.' >&2
  exit 1
}

# --- Static guard (needs no chezmoi): no repository path from the raw sourceDir.
for template in "${TEMPLATES[@]}"; do
  while IFS= read -r line; do
    [[ "$line" == *'.chezmoi.sourceDir'* ]] || continue
    if [[ "$line" != *'dir .chezmoi.sourceDir'* ]]; then
      printf '%s: .chezmoi.sourceDir used without dir.\n' "$template" >&2
      printf '  %s\n' "$line" >&2
      printf '  .chezmoiroot makes .chezmoi.sourceDir the chezmoi/ subdirectory.\n' >&2
      exit 1
    fi
  done <"$template"
done

# --- Static: target detection and the ignore file.
assert_match 'hasKey \.chezmoi "kernel"' "$ROOT/chezmoi/.chezmoi.toml.tmpl"
assert_match 'hasKey \.chezmoi\.kernel "osrelease"' "$ROOT/chezmoi/.chezmoi.toml.tmpl"
assert_match 'microsoft' "$ROOT/chezmoi/.chezmoi.toml.tmpl"
assert_match '^README\.md$' "$ROOT/chezmoi/.chezmoiignore"
assert_match '^AGENTS\.md$' "$ROOT/chezmoi/.chezmoiignore"

if ! command -v chezmoi >/dev/null 2>&1; then
  if [[ "${REQUIRE_CHEZMOI:-0}" == "1" ]]; then
    echo 'chezmoi is required when REQUIRE_CHEZMOI=1.' >&2
    exit 1
  fi
  echo 'Chezmoi templates: static checks OK; chezmoi not installed, template execution skipped'
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FIXTURES=(wsl.toml linux.toml full.toml gpg.toml)

# --- Dynamic: every template executes under every fixture.
for fixture in "${FIXTURES[@]}"; do
  for template in "${TEMPLATES[@]}"; do
    render "$fixture" "$template" >/dev/null
  done
done

# --- The data template: keys, defaults and detected values.
TOML_TMPL="$ROOT/chezmoi/.chezmoi.toml.tmpl"
rendered="$(render linux.toml "$TOML_TMPL")"
for key in gitName gitEmail gitSigningMethod gitSigningKey workGitDir workGitEmail \
  profiles shell target ephemeral machineName; do
  grep -qE "^$key = " <<<"$rendered" || {
    echo ".chezmoi.toml.tmpl does not emit data key: $key" >&2
    exit 1
  }
done
grep -qx 'gitSigningMethod = "ssh"' <<<"$rendered" || {
  echo 'linux.toml: gitSigningMethod is not "ssh".' >&2
  exit 1
}
grep -qE '^target = "(linux|wsl)"$' <<<"$rendered" || {
  echo 'target must be "linux" or "wsl".' >&2
  exit 1
}
# The rendered output is itself a chezmoi config, so it must parse as one.
printf '%s\n' "$rendered" >"$TMP/rendered.toml"
chezmoi execute-template --config "$TMP/rendered.toml" --source "$ROOT/chezmoi" \
  <<<'{{ .shell }}' >/dev/null

# Defaults with no prior config: signing is ssh, the shell is zsh, the work-email
# split is off, and the profile default matches DEFAULT_PROFILES.
: >"$TMP/empty.toml"
defaults="$(chezmoi execute-template --init \
  --promptString 'Git user.name=Test,Git user.email=test@example.invalid' \
  --config "$TMP/empty.toml" --source "$ROOT/chezmoi" <"$TOML_TMPL")"
for expect in 'gitSigningMethod = "ssh"' 'gitSigningKey = "~/.ssh/id_ed25519.pub"' \
  'shell = "zsh"' 'workGitEmail = ""' 'workGitDir = "~/work"' 'gitName = "Test"'; do
  grep -qxF "$expect" <<<"$defaults" || {
    printf 'default render lacks: %s\n' "$expect" >&2
    exit 1
  }
done
# shellcheck source=script/lib/profiles.sh
source "$ROOT/script/lib/profiles.sh"
want="profiles = [\"${DEFAULT_PROFILES//,/\", \"}\"]"
got="$(grep -E '^profiles = ' <<<"$defaults")"
# toToml may wrap or reorder whitespace; compare the quoted names only.
[[ "$(grep -oE '"[^"]+"' <<<"$got" | tr -d '\n')" == "$(grep -oE '"[^"]+"' <<<"$want" | tr -d '\n')" ]] || {
  printf 'default profiles %s != DEFAULT_PROFILES %s\n' "$got" "$want" >&2
  exit 1
}

# --- Git: ssh signing by default, openpgp on request, work split only when set.
git_ssh="$(render linux.toml "$ROOT/chezmoi/dot_gitconfig.tmpl")"
for expect in 'format = ssh' 'allowedSignersFile' 'autocrlf = false' 'gpgsign = true'; do
  grep -qF -- "$expect" <<<"$git_ssh" || {
    printf '.gitconfig (ssh) lacks: %s\n' "$expect" >&2
    exit 1
  }
done
grep -qE '^[[:space:]]*signingkey = "~/\.ssh/id_ed25519\.pub"' <<<"$git_ssh" || {
  echo '.gitconfig (ssh) signingkey is not the per-machine key path.' >&2
  exit 1
}
! grep -q 'includeIf' <<<"$git_ssh" || {
  echo '.gitconfig has includeIf with no workGitEmail.' >&2
  exit 1
}
# The only credential helper is gh, scoped to github.com; no keychain helper.
! grep -qE 'helper = (osxkeychain|store|cache)' <<<"$git_ssh" || {
  echo '.gitconfig sets a non-gh credential helper.' >&2
  exit 1
}
grep -qF 'git credential' <<<"$git_ssh" || grep -qF 'auth git-credential' <<<"$git_ssh" || {
  echo '.gitconfig lacks the gh credential helper.' >&2
  exit 1
}
git_work="$(render full.toml "$ROOT/chezmoi/dot_gitconfig.tmpl")"
grep -qF 'includeIf "gitdir:' <<<"$git_work" || {
  echo '.gitconfig lacks includeIf when workGitEmail is set.' >&2
  exit 1
}
grep -qF 'work@example.invalid' <<<"$(render full.toml "$ROOT/chezmoi/dot_config/git/config-work.tmpl")" || {
  echo 'config-work lacks the work email.' >&2
  exit 1
}
git_gpg="$(render gpg.toml "$ROOT/chezmoi/dot_gitconfig.tmpl")"
grep -qF 'format = openpgp' <<<"$git_gpg" || {
  echo '.gitconfig (gpg) lacks format = openpgp.' >&2
  exit 1
}
! grep -q 'allowedSignersFile' <<<"$git_gpg" || {
  echo '.gitconfig (gpg) carries ssh signing settings.' >&2
  exit 1
}

# --- SSH: Ubuntu's ssh must accept the rendered config. `ssh -G` parses it,
# including every algorithm allowlist, without connecting. The test uses whichever
# ssh is on PATH; CI and the container gate run it on Ubuntu's.
if command -v ssh >/dev/null 2>&1; then
  render linux.toml "$ROOT/chezmoi/private_dot_ssh/config.tmpl" >"$TMP/ssh_config"
  ssh_out="$(ssh -G -F "$TMP/ssh_config" example.invalid)" || {
    echo 'ssh -G rejected the rendered ssh config.' >&2
    exit 1
  }
  for expect in 'identitiesonly yes' 'forwardagent no' 'identityfile ~/.ssh/id_ed25519'; do
    grep -qxF "$expect" <<<"$ssh_out" || {
      printf 'ssh -G output lacks: %s\n' "$expect" >&2
      exit 1
    }
  done
elif [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
  echo 'ssh is required when REQUIRE_LINTERS=1.' >&2
  exit 1
else
  echo '  ssh -G check: ssh not installed, skipped'
fi
ssh_src="$(render linux.toml "$ROOT/chezmoi/private_dot_ssh/config.tmpl")"
[[ "$(grep -v '^[[:space:]]*#' <<<"$ssh_src" | grep -m1 -v '^[[:space:]]*$')" == 'Include ~/.ssh/config.d/*' ]] || {
  echo 'ssh config: Include ~/.ssh/config.d/* is not the first directive.' >&2
  exit 1
}

# --- .chezmoiignore keeps repository documents out of $HOME.
for fixture in "${FIXTURES[@]}"; do
  ignored="$(render "$fixture" "$ROOT/chezmoi/.chezmoiignore")"
  grep -qx 'AGENTS.md' <<<"$ignored" || {
    echo '.chezmoiignore does not ignore AGENTS.md' >&2
    exit 1
  }
done

echo "Chezmoi templates: OK (${#TEMPLATES[@]} templates x ${#FIXTURES[@]} fixtures)"
