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
