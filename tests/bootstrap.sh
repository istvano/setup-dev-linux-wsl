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
# HOME is a fresh temporary directory so the operator's own chezmoi config is never read.
HOME_T="$(mktemp -d)"
trap 'rm -rf "$HOME_T"' EXIT
bs() {
  env -u WSL_DISTRO_NAME -u XDG_CONFIG_HOME HOME="$HOME_T" OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" UNAME_M=x86_64 \
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
# Exit codes: argument errors are 1, --help is 0.
rc=0
"$B" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || {
  echo "bootstrap with no arguments must exit 1, got $rc" >&2
  exit 1
}
rc=0
"$B" frobnicate >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || {
  echo "unknown subcommand must exit 1, got $rc" >&2
  exit 1
}
"$B" --help >/dev/null || {
  echo "--help must exit 0" >&2
  exit 1
}
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
for bad in 'A,B' 'A=B' 'A"B'; do
  err="$(bs apply --non-interactive --git-name "$bad" --git-email t@example.invalid 2>&1 || true)"
  [[ "$err" == *"must not contain"* ]] || {
    printf 'git-name %q: expected a comma/= rejection, got: %s\n' "$bad" "$err" >&2
    exit 1
  }
done

# --- A recorded chezmoi config is the source of truth: a conflicting flag fails closed
# before any step runs, naming the config file and the [data] key to edit.
if command -v chezmoi >/dev/null 2>&1; then
  env -u XDG_CONFIG_HOME HOME="$HOME_T" chezmoi init --source "$ROOT/chezmoi" --promptDefaults \
    --promptString 'Git user.name=Rec,Git user.email=rec@example.invalid' \
    --promptMultichoice 'Workstation profiles=core' >/dev/null 2>&1
  [[ -f "$HOME_T/.config/chezmoi/chezmoi.toml" ]] || {
    echo "test setup: chezmoi init wrote no config" >&2
    exit 1
  }
  conflict_case() {
    local fragment="$1" key="$2" err
    shift 2
    if err="$(bs apply "$@" 2>&1 >"$out.stdout")"; then
      echo "conflicting $key must fail" >&2
      exit 1
    fi
    [[ "$err" == *"chezmoi.toml"* && "$err" == *"[data] $key"* ]] || {
      printf 'conflict %s: stderr must name chezmoi.toml and [data] %s, got: %s\n' "$fragment" "$key" "$err" >&2
      exit 1
    }
    ! grep -q '==> Step' "$out.stdout" || {
      echo "conflict $key: a step ran before the refusal" >&2
      exit 1
    }
  }
  out="$(mktemp)"
  conflict_case shell shell --shell fish
  conflict_case profiles profiles --profiles core,dev
  conflict_case name gitName --git-name Other --git-email rec@example.invalid
  conflict_case email gitEmail --git-name Rec --git-email other@example.invalid
  rm -f "$out" "$out.stdout"

  # --- F1: a re-run must not feed the recorded identity back through chezmoi's prompt
  # flags. --promptString is a comma-separated key=value list, so a recorded name an
  # interactive first run accepted (here with ', ' and '"') would make every later
  # `chezmoi init` fail. A copy of bootstrap runs `apply` with every step but chezmoi
  # stubbed out; the real chezmoi does the init, a wrapper logs its arguments and
  # stubs status and apply, so nothing touches this machine.
  # Under HOME_T, so the EXIT trap removes it even when an assertion fails.
  rerun_tree="$(mktemp -d "$HOME_T/rerun.XXXXXX")"
  real_chezmoi="$(command -v chezmoi)"
  mkdir -p "$rerun_tree/script" "$rerun_tree/brew/bin" "$rerun_tree/home/.config/chezmoi"
  cp "$B" "$rerun_tree/bootstrap"
  cp -R "$ROOT/script/lib" "$rerun_tree/script/lib"
  cp -R "$ROOT/chezmoi" "$rerun_tree/chezmoi"
  for stub in apt-base install-homebrew packages verify; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$rerun_tree/script/$stub"
    chmod +x "$rerun_tree/script/$stub"
  done
  # activate_homebrew evals `brew shellenv`; this one only puts the wrapper first on PATH.
  cat >"$rerun_tree/brew/bin/brew" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == shellenv ]] && printf 'export PATH="%s:\$PATH"\n' "$rerun_tree/brew/bin"
exit 0
EOF
  cat >"$rerun_tree/brew/bin/chezmoi" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$rerun_tree/chezmoi.log"
case "\${1:-}" in
  status | apply) exit 0 ;;
esac
exec "$real_chezmoi" "\$@"
EOF
  chmod +x "$rerun_tree/brew/bin/brew" "$rerun_tree/brew/bin/chezmoi"
  cat >"$rerun_tree/home/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$rerun_tree"
[data]
gitName = "Doe, Jane \"JD\""
gitEmail = "jd@example.invalid"
gitSigningMethod = "ssh"
gitSigningKey = "~/.ssh/id_ed25519.pub"
workGitDir = "~/work"
workGitEmail = ""
profiles = ["core"]
shell = "zsh"
EOF
  if ! rerun_err="$(env -u WSL_DISTRO_NAME -u XDG_CONFIG_HOME HOME="$rerun_tree/home" \
    BREW_PREFIX="$rerun_tree/brew" OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" UNAME_M=x86_64 \
    KERNEL_OSRELEASE_FILE="$FX/osrelease/plain" "$rerun_tree/bootstrap" apply --non-interactive 2>&1)"; then
    printf 'F1: re-run with a recorded name containing ", " and a quote failed:\n%s\n' "$rerun_err" >&2
    exit 1
  fi
  init_line="$(grep '^init ' "$rerun_tree/chezmoi.log" || true)"
  [[ -n "$init_line" ]] || {
    echo 'F1: the re-run never called chezmoi init' >&2
    exit 1
  }
  [[ "$init_line" != *Doe* && "$init_line" != *jd@example* && "$init_line" != *promptString* ]] || {
    printf 'F1: chezmoi init was given recorded identity values: %s\n' "$init_line" >&2
    exit 1
  }
  # chezmoi's prompt*Once kept the record: the name survived the re-init unchanged.
  grep -qxF 'gitName = "Doe, Jane \"JD\""' "$rerun_tree/home/.config/chezmoi/chezmoi.toml" || {
    echo 'F1: the recorded gitName did not survive chezmoi init:' >&2
    cat "$rerun_tree/home/.config/chezmoi/chezmoi.toml" >&2
    exit 1
  }
  rm -rf "$rerun_tree"

  # Standalone verify reads the same record; without a config it must fail clearly.
  rm -rf "$HOME_T/.config"
  err="$(env -u WSL_DISTRO_NAME -u XDG_CONFIG_HOME HOME="$HOME_T" OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" \
    UNAME_M=x86_64 KERNEL_OSRELEASE_FILE="$FX/osrelease/plain" "$ROOT/script/verify" 2>&1 >/dev/null || true)"
  [[ "$err" == *"not initialised"* ]] || {
    printf 'verify without chezmoi config must say it is not initialised, got: %s\n' "$err" >&2
    exit 1
  }
elif [[ "${REQUIRE_CHEZMOI:-0}" == 1 ]]; then
  echo "chezmoi is required when REQUIRE_CHEZMOI=1." >&2
  exit 1
else
  echo "SKIP: chezmoi not found; conflict handling not tested"
fi

# --- Unsupported OS fails before any step is printed, and the error names the OS.
out="$(mktemp)"
trap 'rm -rf "$HOME_T"; rm -f "${out:-}" "${out:-}.err" "${out:-}.stdout"' EXIT
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
# chezmoi status must be captured, not read through process substitution (a failure
# there is swallowed); a foreign config is backed up before init rewrites it.
refute_match '< <\(chezmoi status' "$B"
assert_match 'status_out="\$\(chezmoi status' "$B"
n_backup="$(line_of '^[[:space:]]*backup_foreign_config$')"
((n_backup < $(line_of 'chezmoi init --source'))) || {
  echo "backup_foreign_config must run before chezmoi init" >&2
  exit 1
}
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
