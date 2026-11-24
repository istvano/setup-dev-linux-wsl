#!/usr/bin/env bash
# Argument handling, guard ordering and step order of ./bootstrap. Nothing here runs a
# real apply: every case is refused before the first step, or is a static check.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
FX="$ROOT/tests/fixtures"
B="$ROOT/bootstrap"

[[ -x "$B" ]] || {
  echo "bootstrap is missing or not executable" >&2
  exit 1
}
[[ -x "$ROOT/script/verify" ]] || {
  echo "script/verify is missing or not executable" >&2
  exit 1
}

# --- Argument refusals. The fixtures make the machine look supported (Ubuntu 26.04,
# x86_64, plain Linux), so each refusal is for the argument and not for the host.
bs() {
  env -u WSL_DISTRO_NAME OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" UNAME_M=x86_64 \
    KERNEL_OSRELEASE_FILE="$FX/osrelease/plain" "$B" "$@"
}
# refuse DESCRIPTION EXPECTED_STDERR_FRAGMENT ARGS...
refuse() {
  local description="$1" fragment="$2" err
  shift 2
  if err="$(bs "$@" 2>&1 >/dev/null)"; then
    printf 'must fail: %s\n' "$description" >&2
    exit 1
  fi
  [[ "$err" == *"$fragment"* ]] || {
    printf '%s: expected "%s" in stderr, got: %s\n' "$description" "$fragment" "$err" >&2
    exit 1
  }
}
refute_command "bootstrap with no subcommand must fail" "$B"
refuse "unknown subcommand" "Usage" frobnicate
refuse "--target mac" "Unknown --target" apply --target mac
refuse "--target wsl on plain linux" "Requested --target wsl" apply --target wsl
refuse "--profiles nope" "Unknown profile: nope" apply --profiles nope
refuse "--shell bash" "Unknown --shell" apply --shell bash
refuse "--non-interactive without identity" "--git-name and --git-email" apply --non-interactive
refuse "--non-interactive with only a name" "--git-name and --git-email" \
  apply --non-interactive --git-name T
refuse "option swallowed as a value" "requires a value" apply --profiles --shell fish

# chezmoi's --promptString is a comma-separated key=value list, so a comma or '='
# in a value would be mangled into another key. Reject, naming the problem.
for bad in 'A,B' 'A=B'; do
  err="$(bs apply --non-interactive --git-name "$bad" --git-email t@example.invalid 2>&1 || true)"
  [[ "$err" == *"must not contain"* ]] || {
    printf 'git-name %q: expected a comma/= rejection, got: %s\n' "$bad" "$err" >&2
    exit 1
  }
done

# --- Unsupported OS fails before any step is printed, and the error names the OS.
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
if OS_RELEASE_FILE="$FX/os-release/debian-13" UNAME_M=x86_64 \
  "$B" plan >"$out" 2>"$out.err"; then
  echo "plan on debian 13 must fail" >&2
  exit 1
fi
if grep -q -E '^==>|Step' "$out" || [[ -s "$out" ]]; then
  echo "plan printed output before refusing an unsupported OS:" >&2
  cat "$out" >&2
  exit 1
fi
grep -q 'debian' "$out.err" || {
  echo "stderr must name the OS:" >&2
  cat "$out.err" >&2
  exit 1
}
rm -f "$out.err"

# --- Static: guards, then apt-base, install-homebrew, packages, chezmoi, verify.
line_of() {
  local n
  n="$(grep -n -E -m1 -- "$1" "$B" | cut -d: -f1)"
  [[ -n "$n" ]] || {
    printf 'bootstrap has no line matching: %s\n' "$1" >&2
    exit 1
  }
  printf '%s\n' "$n"
}
prev=0
for pattern in \
  '^[[:space:]]*require_bash5$' \
  '^[[:space:]]*require_not_root$' \
  '^[[:space:]]*require_x86_64$' \
  '^[[:space:]]*require_supported_ubuntu$' \
  '^[[:space:]]*require_target ' \
  '^[[:space:]]*validate_profiles ' \
  'run_step .*script/apt-base' \
  'run_step .*script/install-homebrew' \
  'run_step .*script/packages' \
  'apply_chezmoi$' \
  'run_step .*script/verify'; do
  n="$(line_of "$pattern")"
  ((n > prev)) || {
    printf 'bootstrap order wrong at: %s (line %s, previous %s)\n' "$pattern" "$n" "$prev" >&2
    exit 1
  }
  prev="$n"
done

# --- Static: the properties the brief and rulings require.
assert_match 'chezmoi init --source|"init" --source|init --source' "$B"
assert_match '[-]{2}promptDefaults' "$B"
assert_match '[-]{2}promptMultichoice' "$B"
assert_match 'backup_file' "$B"
refute_match 'chezmoi init[^#]*--apply' "$B"
refute_match 'sudo' "$B"
refute_match '\bchsh\b' "$B"
# The prompt texts bootstrap passes must still be the template's prompt texts.
for key in PROMPT_GIT_NAME PROMPT_GIT_EMAIL PROMPT_PROFILES PROMPT_SHELL; do
  text="$(sed -n "s/^$key=\"\(.*\)\"\$/\1/p" "$B")"
  [[ -n "$text" ]] || {
    echo "bootstrap does not define $key" >&2
    exit 1
  }
  grep -F -q -- "\"$text\"" "$ROOT/chezmoi/.chezmoi.toml.tmpl" || {
    printf 'template no longer has the prompt text: %s\n' "$text" >&2
    exit 1
  }
done
# plan returns before chezmoi init can run: the init lives only in apply_chezmoi, after
# its plan early-return.
n_ret="$(line_of 'plan_chezmoi$')"
n_init="$(line_of 'chezmoi init --source')"
((n_ret < n_init)) || {
  echo "chezmoi init must come after the plan early return" >&2
  exit 1
}

echo 'bootstrap tests passed.'
