#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ -f "$ROOT/apt/base.list" ]] || fail "Missing apt/base.list"

# Every non-comment, non-blank line is "package  # purpose".
while IFS= read -r line; do
  [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[a-z0-9][a-z0-9+.-]+[[:space:]]+#\ .+$ ]] || fail "Malformed apt/base.list line: $line"
done <"$ROOT/apt/base.list"

# Containers own docker; the NVIDIA driver belongs to the Windows host or the distro.
refute_match '^(docker\.io|podman-docker|cuda-drivers|nvidia-[a-z0-9-]+)[[:space:]]' "$ROOT/apt"

[[ -x "$ROOT/script/apt-base" ]] || fail "script/apt-base is missing or not executable"

# Usage errors exit 1, like every other script (2 is not a usage convention here).
for args in --bogus '--check extra'; do
  status=0
  # shellcheck disable=SC2086  # deliberate split: "--check extra" is two arguments
  "$ROOT/script/apt-base" $args >/dev/null 2>&1 || status=$?
  [[ "$status" -eq 1 ]] || fail "apt-base $args should exit 1 (usage error), got $status"
done

# Behaviour: needs dpkg-query (Debian/Ubuntu only).
if ! command -v dpkg-query >/dev/null 2>&1; then
  if [[ "${REQUIRE_LINTERS:-0}" == 1 ]]; then
    fail "dpkg-query is missing and REQUIRE_LINTERS=1: cannot test apt-base --check"
  fi
  echo 'SKIP: dpkg-query not found; apt-base --check behaviour not tested (run on Debian/Ubuntu)'
  echo 'apt tests passed.'
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'bash  # present everywhere\n' >"$tmp/present.list"
printf 'definitely-not-a-package-xyz  # absent\n' >"$tmp/absent.list"

APT_BASE_LIST="$tmp/present.list" "$ROOT/script/apt-base" --check >/dev/null ||
  fail "apt-base --check should succeed when every package is installed"

status=0
out="$(APT_BASE_LIST="$tmp/absent.list" "$ROOT/script/apt-base" --check 2>&1)" || status=$?
[[ "$status" -eq 1 ]] || fail "apt-base --check should exit 1 for a missing package (got $status)"
[[ "$out" == *definitely-not-a-package-xyz* ]] || fail "apt-base --check should name the missing package"

echo 'apt tests passed.'
