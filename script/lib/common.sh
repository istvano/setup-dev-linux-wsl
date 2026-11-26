#!/usr/bin/env bash
# Shared helpers for the repository's scripts. Sourced, never run.
#
# This file is parsed by whatever bash starts script/test, including macOS's 3.2,
# so that require_bash5 can refuse cleanly instead of dying on a parse error. Keep
# the syntax here to what bash 3.2 can read; the rest of the repository needs bash 5.

set -Eeuo pipefail
IFS=$'\n\t'

# C_BOLD is part of the palette this library publishes to sourcing scripts even
# though nothing in this file uses it.
# shellcheck disable=SC2034
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""
  C_BLUE=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_BOLD=""
fi

log() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
success() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
  printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Refuse to continue under bash older than 5. The repository's scripts rely on bash 5
# features and its tests do not port the Mac's bash 3.2 compatibility checks.
require_bash5() {
  ((BASH_VERSINFO[0] >= 5)) || die "bash 5 or newer is required (this is ${BASH_VERSION})."
}

# Reject a missing value, and an option swallowed as the value: `--profiles --shell fish`
# would otherwise set the profile list to "--shell" and fail later on "fish", sending
# you looking in the wrong place.
require_value() {
  local flag="$1" value="${2-}"
  [[ -n "$value" ]] || die "$flag requires a value."
  [[ "$value" != --* ]] ||
    die "$flag requires a value, but got the option '$value'."
}

# Ask a yes/no question. ASSUME_YES=1 answers yes; with no terminal on stdin the
# answer is no, because silence must never be consent.
confirm() {
  local prompt="$1" answer
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "Not asking '$prompt' because there is no terminal on stdin; assuming no.
Set ASSUME_YES=1 to answer yes without a prompt."
    return 1
  fi
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Copy PATH to PATH.backup.<UTC timestamp> and print the backup path. Nothing to
# back up is not an error and prints nothing.
backup_file() {
  local path="$1" backup
  [[ -e "$path" || -L "$path" ]] || return 0
  backup="${path}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -R "$path" "$backup"
  printf '%s\n' "$backup"
}

# Write stdin to PATH atomically: a temp file in the same directory (so mv is a rename
# on one filesystem), then mv. A failed writer leaves the original untouched.
atomic_write() {
  local path="$1" tmp
  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp "$path.XXXXXX")"
  # shellcheck disable=SC2064  # expand $tmp now: the trap must remove this file
  trap "rm -f '$tmp'" RETURN
  cat >"$tmp"
  mv "$tmp" "$path"
}

# --- Platform detection and preflight guards -------------------------------------
# The file paths below are overridable so tests can point them at fixtures.

# Print "wsl" when the kernel reports Microsoft's build or WSL_DISTRO_NAME is set,
# otherwise "linux".
detect_target() {
  local file="${KERNEL_OSRELEASE_FILE:-/proc/sys/kernel/osrelease}" release=""
  [[ -r "$file" ]] && release="$(cat "$file")"
  shopt -s nocasematch
  if [[ "$release" == *microsoft* || -n "${WSL_DISTRO_NAME:-}" ]]; then
    shopt -u nocasematch
    printf 'wsl\n'
  else
    shopt -u nocasematch
    printf 'linux\n'
  fi
}

# Die unless the detected target is EXPECTED (wsl or linux).
require_target() {
  local expected="$1" actual
  actual="$(detect_target)"
  [[ "$expected" == "$actual" ]] ||
    die "Requested --target $expected but this machine is $actual."
}

# Only Ubuntu 26.04 is supported. os-release is sourced in a subshell, not grepped.
require_supported_ubuntu() {
  local file="${OS_RELEASE_FILE:-/etc/os-release}" found
  [[ -r "$file" ]] || die "Cannot read $file; only Ubuntu 26.04 is supported."
  found="$(
    ID="" VERSION_ID=""
    # shellcheck disable=SC1090  # the path is deliberately variable
    . "$file"
    printf '%s %s' "${ID:-unknown}" "${VERSION_ID:-unknown}"
  )"
  [[ "$found" == "ubuntu 26.04" ]] ||
    die "Only Ubuntu 26.04 is supported; found: $found."
}

require_x86_64() {
  local arch="${UNAME_M:-$(uname -m)}"
  [[ "$arch" == "x86_64" ]] || die "Only x86_64 is supported; found: $arch."
}

# Returns 0 when running as root. Separate so tests can stub it (EUID is readonly).
is_root() { [[ "${EUID}" -eq 0 ]]; }

require_not_root() {
  if is_root; then
    die "Run as your normal user; the scripts call sudo themselves."
  fi
}

# Print any .git directories under MNT_ROOT/* (default /mnt, the Windows drives under
# WSL) to depth 4. Repos on /mnt are slow and have the wrong permissions and line
# endings; verify reports them. One repository is exempt: the companion Windows host
# repository (origin ending in /setup-dev-win), which runs from Windows and must live
# there (ADR-012). Its origin is read from the config file, not with git, so a
# checkout owned by another user ("dubious ownership") cannot hide or break the check.
repos_under_mnt() {
  local root="${MNT_ROOT:-/mnt}" dir gitdir origin
  for dir in "$root"/*; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r gitdir; do
      origin="$(git config --file "$gitdir/config" --get remote.origin.url 2>/dev/null || true)"
      origin="${origin%/}"
      origin="${origin%.git}"
      [[ "$origin" == */setup-dev-win ]] && continue
      printf '%s\n' "$gitdir"
    done < <(find "$dir" -maxdepth 4 -type d -name .git 2>/dev/null || true)
  done
}

# --- Homebrew on Linux -------------------------------------------------------------
# The default prefix is the one Homebrew's bottles are built for. Overridable so tests
# can point at a temporary directory.
BREW_PREFIX="${BREW_PREFIX:-/home/linuxbrew/.linuxbrew}"

# Put Homebrew on PATH for this process. Returns 1 when it is not installed.
activate_homebrew() {
  [[ -x "$BREW_PREFIX/bin/brew" ]] || return 1
  # eval is vendor shell initialisation: `brew shellenv` prints export statements.
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
}

# Where script/render-brewfile writes by default and script/packages reads from, so
# the location has one definition.
default_brewfile_path() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/setup-dev-linux-wsl/Brewfile"
}

# --- chezmoi data ------------------------------------------------------------------
# Once a chezmoi config exists it is the record of what this machine was set up with:
# the template's prompt*Once functions return the stored value and ignore flags. So
# bootstrap and verify read it rather than guess.
chezmoi_config_path() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml"
}

# chezmoi_data TEMPLATE_EXPR: print the expression's value from the chezmoi data, e.g.
# chezmoi_data '.shell' or chezmoi_data '.profiles | join ","'. Fails when chezmoi
# is missing or the key is absent.
chezmoi_data() {
  command_exists chezmoi || return 1
  chezmoi execute-template "{{ $1 }}"
}
