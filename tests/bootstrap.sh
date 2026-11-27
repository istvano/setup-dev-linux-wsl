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
# Every refusal below is reached the same way by plan and apply (the guards and the
# chezmoi-record reconciliation run before either does anything), so the tests use
# plan: if a guard ever regressed, the test would run read-only checks, not installs.
refuse "unknown subcommand" "Usage" frobnicate
refuse "--target mac" "Unknown --target" plan --target mac
refuse "--target wsl on plain linux" "Requested --target wsl" plan --target wsl
refuse "--profiles nope" "Unknown profile: nope" plan --profiles nope
# #9: chezmoi, mise and uv come from core; a profile list without it cannot work.
refuse "--profiles without core" "must include core" plan --profiles dev,security
refuse "--shell bash" "Unknown --shell" plan --shell bash
refuse "--non-interactive without identity" "--git-name and --git-email" plan --non-interactive
refuse "--non-interactive with only a name" "--git-name and --git-email" \
  plan --non-interactive --git-name T
refuse "option swallowed as a value" "requires a value" plan --profiles --shell fish

# runtime-docker and gpu-nvidia are linux-target only for now: refused on --target wsl
# with the milestone message, by the guards, before any step is printed or run.
bs_wsl() {
  env -u XDG_CONFIG_HOME HOME="$HOME_T" WSL_DISTRO_NAME=test OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" UNAME_M=x86_64 \
    KERNEL_OSRELEASE_FILE="$FX/osrelease/wsl" "$B" "$@"
}
for prof in runtime-docker gpu-nvidia; do
  for mode in plan apply; do
    rc=0
    out="$(bs_wsl "$mode" --target wsl --profiles "core,$prof" 2>&1)" || rc=$?
    [[ "$rc" -ne 0 ]] || {
      printf '%s --profiles core,%s on wsl must fail\n' "$mode" "$prof" >&2
      exit 1
    }
    [[ "$out" == *"$prof is for --target linux for now; Docker and GPU inside WSL arrive with the WSL integration milestone (TASKS.md)."* ]] || {
      printf 'wrong refusal for %s on wsl: %s\n' "$prof" "$out" >&2
      exit 1
    }
    [[ "$out" != *"==> Step"* ]] || {
      printf 'a step ran before the %s refusal: %s\n' "$prof" "$out" >&2
      exit 1
    }
  done
done
# The other new profiles are accepted on wsl: the refusal there is only for those two.
for prof in ai-agents cloud-gcp cloud-azure; do
  out="$(bs_wsl plan --target wsl --profiles "core,$prof" 2>&1 || true)"
  [[ "$out" != *"is for --target linux"* ]] || {
    printf '%s must not be refused on wsl\n' "$prof" >&2
    exit 1
  }
done

# chezmoi's --promptString is a comma-separated key=value list, so a comma or '='
# in a value would be mangled into another key. Reject, naming the problem.
for bad in 'A,B' 'A=B' 'A"B'; do
  err="$(bs plan --non-interactive --git-name "$bad" --git-email t@example.invalid 2>&1 || true)"
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
    if err="$(bs plan "$@" 2>&1 >"$out.stdout")"; then
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
  # #9 also holds for a recorded profile list: a record without core is refused.
  cfg="$HOME_T/.config/chezmoi/chezmoi.toml"
  cp "$cfg" "$cfg.orig"
  sed -i.tmp 's/^profiles = .*/profiles = ["dev"]/' "$cfg"
  refuse "recorded profiles without core" "must include core" plan
  mv "$cfg.orig" "$cfg"
  rm -f "$cfg.tmp"

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
  for stub in apt-base apt-vendor docker-setup install-homebrew packages verify; do
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

  # --- F3 (R20): verify names `mise install` as the remedy for missing runtimes. Every
  # check verify runs is read-only; stubs stand in for mise and for ssh (the identity
  # check's GitHub probe), and the rest simply fail on this host, which is expected.
  stubs="$(mktemp -d "$HOME_T/stubs.XXXXXX")"
  printf '#!/bin/sh\necho "node  24.0.0  (missing)"\n' >"$stubs/mise"
  printf '#!/bin/sh\nexit 255\n' >"$stubs/ssh"
  chmod +x "$stubs/mise" "$stubs/ssh"
  verify_out="$(env -u WSL_DISTRO_NAME -u XDG_CONFIG_HOME HOME="$HOME_T" PATH="$stubs:$PATH" \
    OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" UNAME_M=x86_64 KERNEL_OSRELEASE_FILE="$FX/osrelease/plain" \
    "$ROOT/script/verify" --target linux 2>&1 || true)"
  [[ "$verify_out" == *"FAIL: mise runtimes installed"* && "$verify_out" == *"Remedy: run \`mise install\`"* ]] || {
    printf 'verify must fail the mise check and name "mise install" as the remedy, got:\n%s\n' "$verify_out" >&2
    exit 1
  }

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
  'run_step "docker conflicts"' \
  'run_step .*script/apt-vendor' \
  'run_step "Docker Engine"' \
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
# The login-shell [ACTION] is the last line of an apply: verify defers it, bootstrap
# prints it after "bootstrap complete" (ADR-007).
# shellcheck disable=SC2016 # literal text of the bootstrap, not an expansion
assert_match 'script/verify" --target "\$target" --defer-shell-action' "$B"
# shellcheck disable=SC2016 # literal text of the bootstrap, not an expansion
[[ "$(grep -v '^[[:space:]]*\(#\|$\)' "$ROOT/bootstrap" | tail -1)" == 'login_shell_action "$shell_choice"' ]] || {
  echo "bootstrap must end with login_shell_action, after \"bootstrap complete\"" >&2
  exit 1
}

# login_shell_action prints the command, never runs it, and is silent when nothing is due.
lsa() { # lsa SELECTED LOGIN_SHELL [PATH-PREFIX]
  (
    # shellcheck source=script/lib/common.sh
    source "$ROOT/script/lib/common.sh"
    PATH="${3:+$3:}$PATH" LOGIN_SHELL_OVERRIDE="$2" login_shell_action "$1"
  ) 2>&1
}
out="$(lsa zsh /bin/bash)"
[[ "$out" == *"[ACTION]"*"Login shell is /bin/bash"* && "$out" == *$'\n  chsh -s /usr/bin/zsh' ]] || {
  printf 'login_shell_action must print the chsh line for zsh, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" != *"/etc/shells"* ]] || {
  echo "zsh is already in /etc/shells; no tee line expected" >&2
  exit 1
}
[[ -z "$(lsa zsh /usr/bin/zsh)" ]] || {
  echo "login_shell_action must be silent when the login shell is already zsh" >&2
  exit 1
}
fakefish="$(mktemp -d)"
printf '#!/bin/sh\n' >"$fakefish/fish"
chmod +x "$fakefish/fish"
out="$(lsa fish /bin/bash "$fakefish")"
[[ "$out" == *"echo $fakefish/fish | sudo tee -a /etc/shells"* && "$out" == *"chsh -s $fakefish/fish"* ]] || {
  printf 'login_shell_action must print the /etc/shells and chsh lines for fish, got:\n%s\n' "$out" >&2
  exit 1
}
rm -rf "$fakefish"
refute_match '^[[:space:]]*(sudo[[:space:]]+)?chsh' "$ROOT/script/lib/common.sh"
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
