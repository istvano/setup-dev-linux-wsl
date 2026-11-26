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

# --- #8: every rendered run_* hook is valid bash and shellcheck-clean, under every
# fixture. script/shell-files cannot see these (they are templates until rendered),
# so they are linted here. An empty render (a hook gated off by profile) is skipped.
hooks_linted=0
for fixture in "${FIXTURES[@]}"; do
  for template in "${TEMPLATES[@]}"; do
    [[ "$(basename "$template")" == run_* ]] || continue
    rendered_hook="$TMP/hook.sh"
    render "$fixture" "$template" >"$rendered_hook"
    [[ -n "$(tr -d '[:space:]' <"$rendered_hook")" ]] || continue
    bash -n "$rendered_hook" || {
      printf 'bash -n rejects %s rendered with %s\n' "$template" "$fixture" >&2
      exit 1
    }
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck -s bash "$rendered_hook" || {
        printf 'shellcheck rejects %s rendered with %s\n' "$template" "$fixture" >&2
        exit 1
      }
    elif [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
      echo 'shellcheck is required when REQUIRE_LINTERS=1.' >&2
      exit 1
    fi
    hooks_linted=$((hooks_linted + 1))
  done
done
((hooks_linted > 0)) || {
  echo 'No run_* hook was linted; the selector is broken.' >&2
  exit 1
}
command -v shellcheck >/dev/null 2>&1 || echo '  rendered hooks: shellcheck not installed, bash -n only'

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
# F6: the includeIf ends in exactly one slash whether or not workGitDir has one. A
# rendered `gitdir:~/work//` never matches, so the work identity silently turns off.
grep -qxF '[includeIf "gitdir:~/work/"]' <<<"$git_work" || {
  printf '.gitconfig includeIf is not exactly gitdir:~/work/:\n%s\n' "$(grep includeIf <<<"$git_work")" >&2
  exit 1
}
sed 's|^workGitDir = .*|workGitDir = "~/work/"|' "$ROOT/tests/fixtures/chezmoi/full.toml" >"$TMP/work-slash.toml"
git_slash="$(render "$TMP/work-slash.toml" "$ROOT/chezmoi/dot_gitconfig.tmpl")"
grep -qxF '[includeIf "gitdir:~/work/"]' <<<"$git_slash" || {
  printf 'workGitDir with a trailing slash renders a broken includeIf:\n%s\n' "$(grep includeIf <<<"$git_slash")" >&2
  exit 1
}
# F5 (R21): VS Code difftool/mergetool use bare `code`, never a lookPath absolute path:
# on WSL that resolves to /mnt/c/... with spaces, which git's sh splits. The section is
# decided by the detected target, so rendering never depends on the caller's PATH.
refute_match 'lookPath "code"' "$ROOT/chezmoi/dot_gitconfig.tmpl"
git_wsl="$(render wsl.toml "$ROOT/chezmoi/dot_gitconfig.tmpl")"
# shellcheck disable=SC2016  # $LOCAL etc. are git's placeholders, matched literally
for expect in '  cmd = code --wait --diff $LOCAL $REMOTE' \
  '  cmd = code --wait --merge $LOCAL $REMOTE $BASE $MERGED'; do
  grep -qxF -- "$expect" <<<"$git_wsl" || {
    printf '.gitconfig (wsl) lacks: %s\n' "$expect" >&2
    exit 1
  }
done
! grep -q 'tool = vscode' <<<"$git_ssh" || {
  echo '.gitconfig (headless linux) configures the VS Code difftool.' >&2
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

# --- F3 (R20): the runtimes hook fails when mise install fails or mise is missing.
# chezmoi records a run_onchange_ script as done only when it exits 0, so a reported-
# but-swallowed failure would never be retried. Run for real against a stub mise, on a
# PATH without the host's own mise.
RUNTIMES_HOOK="$ROOT/chezmoi/run_onchange_after_20_configure-runtimes.sh.tmpl"
render linux.toml "$RUNTIMES_HOOK" >"$TMP/runtimes.sh"
mkdir -p "$TMP/mise-ok" "$TMP/mise-fail" "$TMP/mise-none"
printf '#!/bin/sh\nexit 0\n' >"$TMP/mise-ok/mise"
printf '#!/bin/sh\necho "stub mise: download failed" >&2\nexit 1\n' >"$TMP/mise-fail/mise"
chmod +x "$TMP/mise-ok/mise" "$TMP/mise-fail/mise"
BASH_BIN="$(command -v bash)"
runtimes_hook() { # runtimes_hook STUB_DIR: prints output; status in $rc
  rc=0
  hook_out="$(PATH="$1:/usr/bin:/bin" "$BASH_BIN" "$TMP/runtimes.sh" 2>&1)" || rc=$?
}
runtimes_hook "$TMP/mise-ok"
((rc == 0)) || {
  printf 'runtimes hook failed although mise install succeeded:\n%s\n' "$hook_out" >&2
  exit 1
}
runtimes_hook "$TMP/mise-fail"
((rc != 0)) || {
  printf 'runtimes hook exited 0 although mise install failed:\n%s\n' "$hook_out" >&2
  exit 1
}
runtimes_hook "$TMP/mise-none"
if ! ((rc != 0)) || [[ "$hook_out" != *"mise is not installed"* ]]; then
  printf 'runtimes hook must fail, naming mise, when mise is missing (rc %s):\n%s\n' "$rc" "$hook_out" >&2
  exit 1
fi

# --- ADR-010: the krew hook, run for real against a stub kubectl. Gated on the
# kubernetes profile; idempotent; a failed plugin install fails the hook so chezmoi
# retries; ~/.krew/bin is created first.
KREW_HOOK="$ROOT/chezmoi/run_onchange_after_28_krew-plugins.sh.tmpl"
sed 's|^profiles = .*|profiles = ["core", "dev"]|' "$ROOT/tests/fixtures/chezmoi/linux.toml" >"$TMP/no-k8s.toml"
[[ -z "$(render "$TMP/no-k8s.toml" "$KREW_HOOK" | tr -d '[:space:]')" ]] || {
  echo 'krew hook renders without the kubernetes profile.' >&2
  exit 1
}
render linux.toml "$KREW_HOOK" >"$TMP/krew.sh"
[[ -s "$TMP/krew.sh" ]] || {
  echo 'krew hook renders empty with the kubernetes profile.' >&2
  exit 1
}
make_kubectl_stub() { # make_kubectl_stub DIR INSTALLED FAIL_PLUGIN
  mkdir -p "$1"
  cat >"$1/kubectl" <<STUB
#!/bin/sh
# stub: kubectl krew {update|list|install NAME}; records installs in \$KREW_LOG
[ "\$1" = krew ] || exit 0
case "\$2" in
  update) exit 0 ;;
  list) printf '%s\n' $2; exit 0 ;;
  install)
    [ "\$3" = "$3" ] && { echo "stub: cannot install \$3" >&2; exit 1; }
    echo "\$3" >>"\$KREW_LOG"
    exit 0 ;;
esac
STUB
  chmod +x "$1/kubectl"
  printf '#!/bin/sh\nexit 0\n' >"$1/kubectl-krew"
  chmod +x "$1/kubectl-krew"
}
krew_hook() { # krew_hook STUB_DIR: output in $hook_out, status in $rc, installs in $TMP/krew.log
  rc=0
  : >"$TMP/krew.log"
  rm -rf "$TMP/khome"
  mkdir -p "$TMP/khome"
  hook_out="$(HOME="$TMP/khome" KREW_LOG="$TMP/krew.log" PATH="$1:/usr/bin:/bin" "$BASH_BIN" "$TMP/krew.sh" 2>&1)" || rc=$?
}
make_kubectl_stub "$TMP/krew-ok" '' none
krew_hook "$TMP/krew-ok"
((rc == 0)) || {
  printf 'krew hook failed with a working krew:\n%s\n' "$hook_out" >&2
  exit 1
}
[[ "$(sort "$TMP/krew.log" | paste -sd, -)" == 'images,neat,tree,view-secret,whoami' ]] || {
  printf 'krew hook installed the wrong plugins: %s\n' "$(paste -sd, "$TMP/krew.log")" >&2
  exit 1
}
[[ -d "$TMP/khome/.krew/bin" ]] || {
  echo 'krew hook did not create ~/.krew/bin.' >&2
  exit 1
}
make_kubectl_stub "$TMP/krew-all" 'neat view-secret tree whoami images' none
krew_hook "$TMP/krew-all"
[[ "$rc" == 0 && ! -s "$TMP/krew.log" ]] || {
  printf 'krew hook is not idempotent (rc %s, installed: %s)\n' "$rc" "$(paste -sd, "$TMP/krew.log")" >&2
  exit 1
}
make_kubectl_stub "$TMP/krew-fail" 'neat' tree
krew_hook "$TMP/krew-fail"
((rc != 0)) || {
  printf 'krew hook exited 0 although a plugin install failed:\n%s\n' "$hook_out" >&2
  exit 1
}
grep -qx 'whoami' "$TMP/krew.log" || {
  echo 'krew hook stopped at the first failure instead of trying the other plugins.' >&2
  exit 1
}
mkdir -p "$TMP/krew-none"
krew_hook "$TMP/krew-none"
((rc != 0)) || {
  echo 'krew hook exited 0 although kubectl is missing.' >&2
  exit 1
}

# --- ADR-015: the uv-tools hook (aider) and the telemetry hook (Go, aider), run for
# real against stubs. Never fatal; no toolchain download just to answer a question.
UVTOOLS_HOOK="$ROOT/chezmoi/run_onchange_after_29_uv-tools.sh.tmpl"
TELEMETRY_HOOK="$ROOT/chezmoi/run_onchange_after_31_telemetry-optout.sh.tmpl"
sed 's|^profiles = .*|profiles = ["core"]|' "$ROOT/tests/fixtures/chezmoi/linux.toml" >"$TMP/core-only.toml"
[[ -z "$(render "$TMP/core-only.toml" "$UVTOOLS_HOOK" | tr -d '[:space:]')" ]] || {
  echo 'uv-tools hook renders without the dev profile.' >&2
  exit 1
}
render linux.toml "$UVTOOLS_HOOK" >"$TMP/uvtools.sh"
render linux.toml "$TELEMETRY_HOOK" >"$TMP/telemetry.sh"
[[ -s "$TMP/uvtools.sh" && -s "$TMP/telemetry.sh" ]] || {
  echo 'uv-tools or telemetry hook renders empty.' >&2
  exit 1
}
grep -v '^[[:space:]]*#' "$TMP/telemetry.sh" >"$TMP/telemetry.code"
refute_match 'mise exec' "$TMP/telemetry.code"
assert_match 'mise which go' "$TMP/telemetry.sh"
assert_match 'uv tool install' "$TMP/uvtools.sh"
refute_match 'aider-chat==' "$TMP/uvtools.sh" # ADR-011: latest stable, no pin (comments say so without the spelling)

STUBS="$TMP/stubs"
mkdir -p "$STUBS/uv-ok" "$STUBS/uv-have" "$STUBS/uv-fail" "$STUBS/mise" "$STUBS/mise-none" "$STUBS/aider" "$STUBS/empty"
cat >"$STUBS/uv-ok/uv" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "tool list") exit 0 ;;
  "tool install") echo "$*" >>"$UV_LOG"; exit 0 ;;
esac
STUB
cat >"$STUBS/uv-have/uv" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "tool list") printf 'aider-chat v0.99.0\n- aider\n'; exit 0 ;;
  "tool install") echo "$*" >>"$UV_LOG"; exit 0 ;;
esac
STUB
cat >"$STUBS/uv-fail/uv" <<'STUB'
#!/bin/sh
[ "$1 $2" = "tool list" ] && exit 0
exit 1
STUB
cat >"$STUBS/mise/mise" <<STUB
#!/bin/sh
# stub: only \`mise which go\` is allowed; anything else (exec, install) is a violation
[ "\$1 \$2" = "which go" ] || { echo "stub mise: unexpected \$*" >>"\$MISE_LOG"; exit 1; }
echo "$STUBS/mise/go"
STUB
cat >"$STUBS/mise/go" <<'STUB'
#!/bin/sh
state="$HOME/.go-telemetry"
case "$1 $2" in
  "telemetry ") cat "$state" 2>/dev/null || echo local ;;
  "telemetry off") echo off >"$state"; echo "go telemetry off" >>"$GO_LOG" ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' >"$STUBS/mise-none/mise"
cat >"$STUBS/aider/aider" <<'STUB'
#!/bin/sh
# stub: refuses to run with stdin attached, as the real one stalls on OpenRouter login
[ -t 0 ] && exit 1
mkdir -p "$HOME/.aider"
echo '{"permanently_disable": true}' >"$HOME/.aider/analytics.json"
exit 1
STUB
chmod +x "$STUBS"/*/*

hook_run() { # hook_run SCRIPT STUB_DIR...: output in $hook_out, status in $rc
  local script="$1" path=""
  shift
  for d in "$@"; do path+="$d:"; done
  rc=0
  rm -rf "$TMP/uhome"
  mkdir -p "$TMP/uhome"
  : >"$TMP/uv.log" && : >"$TMP/go.log" && : >"$TMP/mise.log"
  hook_out="$(HOME="$TMP/uhome" UV_LOG="$TMP/uv.log" GO_LOG="$TMP/go.log" MISE_LOG="$TMP/mise.log" \
    PATH="$path/usr/bin:/bin" "$BASH_BIN" "$script" 2>&1 </dev/null)" || rc=$?
}
# uv-tools: installs aider-chat unpinned on Python 3.12, once.
hook_run "$TMP/uvtools.sh" "$STUBS/uv-ok"
if ! { [[ "$rc" == 0 ]] && grep -qx 'tool install --force --python 3.12 aider-chat' "$TMP/uv.log"; }; then
  printf 'uv-tools hook did not install aider-chat (rc %s):\n%s\n%s\n' "$rc" "$hook_out" "$(cat "$TMP/uv.log")" >&2
  exit 1
fi
hook_run "$TMP/uvtools.sh" "$STUBS/uv-have"
[[ "$rc" == 0 && ! -s "$TMP/uv.log" ]] || {
  printf 'uv-tools hook is not idempotent (rc %s):\n%s\n' "$rc" "$(cat "$TMP/uv.log")" >&2
  exit 1
}
hook_run "$TMP/uvtools.sh" "$STUBS/uv-fail"
((rc == 0)) || {
  printf 'uv-tools hook must not fail when an install fails (rc %s):\n%s\n' "$rc" "$hook_out" >&2
  exit 1
}
hook_run "$TMP/uvtools.sh" "$STUBS/empty"
((rc == 0)) || {
  echo 'uv-tools hook must exit 0 when uv is missing.' >&2
  exit 1
}
# telemetry: Go off through `mise which`, idempotent, never fatal, never a download.
hook_run "$TMP/telemetry.sh" "$STUBS/mise"
if ! { [[ "$rc" == 0 ]] && grep -q 'go telemetry off' "$TMP/go.log" && [[ ! -s "$TMP/mise.log" ]]; }; then
  printf 'telemetry hook did not turn Go telemetry off via mise which (rc %s):\n%s\n%s\n' "$rc" "$hook_out" "$(cat "$TMP/mise.log")" >&2
  exit 1
fi
mkdir -p "$TMP/uhome" && echo off >"$TMP/uhome/.go-telemetry"
rc=0
: >"$TMP/go.log"
hook_out="$(HOME="$TMP/uhome" GO_LOG="$TMP/go.log" MISE_LOG="$TMP/mise.log" PATH="$STUBS/mise:/usr/bin:/bin" "$BASH_BIN" "$TMP/telemetry.sh" 2>&1 </dev/null)" || rc=$?
[[ "$rc" == 0 && ! -s "$TMP/go.log" ]] || {
  echo 'telemetry hook is not idempotent for Go.' >&2
  exit 1
}
hook_run "$TMP/telemetry.sh" "$STUBS/mise-none"
((rc == 0)) || {
  printf 'telemetry hook must exit 0 when mise cannot find go (rc %s):\n%s\n' "$rc" "$hook_out" >&2
  exit 1
}
hook_run "$TMP/telemetry.sh" "$STUBS/aider"
if ! { [[ "$rc" == 0 ]] && grep -q 'permanently_disable' "$TMP/uhome/.aider/analytics.json"; }; then
  printf 'telemetry hook did not record the aider opt-out (rc %s):\n%s\n' "$rc" "$hook_out" >&2
  exit 1
fi

# --- .chezmoiignore keeps repository documents out of $HOME.
for fixture in "${FIXTURES[@]}"; do
  ignored="$(render "$fixture" "$ROOT/chezmoi/.chezmoiignore")"
  grep -qx 'AGENTS.md' <<<"$ignored" || {
    echo '.chezmoiignore does not ignore AGENTS.md' >&2
    exit 1
  }
done

echo "Chezmoi templates: OK (${#TEMPLATES[@]} templates x ${#FIXTURES[@]} fixtures)"
