#!/usr/bin/env bash
# Shared assertions for the repository test suite.

# Bare `! grep ...` disables errexit for the command and treats grep's error
# status (2) as success, so a renamed or missing file makes the assertion pass
# silently. These helpers distinguish "no match" from "grep could not run".

assert_match() {
  local pattern="$1"
  shift
  local status=0
  grep -R -E -q -- "$pattern" "$@" || status=$?
  case "$status" in
    0) return 0 ;;
    1)
      printf 'Expected a match for %s in: %s\n' "$pattern" "$*" >&2
      exit 1
      ;;
    *)
      printf 'grep failed with status %s for %s in: %s\n' "$status" "$pattern" "$*" >&2
      exit 1
      ;;
  esac
}

refute_match() {
  local pattern="$1"
  shift
  local status=0
  grep -R -E -q -- "$pattern" "$@" || status=$?
  case "$status" in
    0)
      printf 'Unexpected match for %s in: %s\n' "$pattern" "$*" >&2
      exit 1
      ;;
    1) return 0 ;;
    *)
      printf 'grep failed with status %s for %s in: %s\n' "$status" "$pattern" "$*" >&2
      exit 1
      ;;
  esac
}

# Assert a command fails, without letting an unexpected success pass.
refute_command() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '%s\n' "$description" >&2
    exit 1
  fi
}

# render FIXTURE TEMPLATE_PATH
#
# Prints the rendered text of one chezmoi template under a fixture's data.
# FIXTURE is a file name under tests/fixtures/chezmoi/ (or a path); TEMPLATE_PATH
# is absolute or relative to <repo>/chezmoi. A template error fails loudly.
# .chezmoi.toml.tmpl is run with --init, since it uses the prompt*Once functions;
# the fixture's data satisfies them, so nothing prompts. execute-template has no
# --promptDefaults (that is `chezmoi init` only); there, a prompt with no data and
# no simulated answer simply yields its default, and --promptString is keyed by
# the PROMPT TEXT, not the data key.
: "${ROOT:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"
render() {
  local fixture="$1" template="$2" config init=() err
  [[ "$fixture" == /* || "$fixture" == */* ]] && config="$fixture" ||
    config="$ROOT/tests/fixtures/chezmoi/$fixture"
  [[ "$template" == /* ]] || template="$ROOT/chezmoi/$template"
  [[ -f "$config" && -f "$template" ]] || {
    printf 'render: missing fixture or template: %s %s\n' "$config" "$template" >&2
    exit 1
  }
  if [[ "$(basename "$template")" == .chezmoi.toml.tmpl ]]; then
    init=(--init --promptString 'Git user.name=Test,Git user.email=test@example.invalid')
  fi
  err="$(mktemp)"
  if ! chezmoi execute-template --config "$config" --source "$ROOT/chezmoi" \
    "${init[@]+"${init[@]}"}" <"$template" 2>"$err"; then
    printf 'render: template error in %s (fixture %s):\n' "$template" "$config" >&2
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  rm -f "$err"
}
