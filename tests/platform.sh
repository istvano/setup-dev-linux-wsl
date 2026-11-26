#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
FX="$ROOT/tests/fixtures"

# Each case runs in a subshell that sources common.sh with the fixture overrides.
in_env() { (
  source "$ROOT/script/lib/common.sh"
  "$@"
); }

expect_eq() {
  [[ "$1" == "$2" ]] || {
    printf 'Expected %s, got %s\n' "$2" "$1" >&2
    exit 1
  }
}

# detect_target
got="$(KERNEL_OSRELEASE_FILE="$FX/osrelease/wsl" in_env detect_target)"
expect_eq "$got" wsl
got="$(
  unset WSL_DISTRO_NAME
  KERNEL_OSRELEASE_FILE="$FX/osrelease/plain" in_env detect_target
)"
expect_eq "$got" linux
got="$(WSL_DISTRO_NAME=dev KERNEL_OSRELEASE_FILE="$FX/osrelease/plain" in_env detect_target)"
expect_eq "$got" wsl

# require_target
plain="$FX/osrelease/plain"
(
  unset WSL_DISTRO_NAME
  KERNEL_OSRELEASE_FILE="$plain" in_env require_target linux
)
if (
  unset WSL_DISTRO_NAME
  KERNEL_OSRELEASE_FILE="$plain" in_env require_target wsl >/dev/null 2>&1
); then
  echo "require_target wsl must fail on a plain Linux machine" >&2
  exit 1
fi
err="$(
  unset WSL_DISTRO_NAME
  KERNEL_OSRELEASE_FILE="$plain" in_env require_target wsl 2>&1 || true
)"
[[ "$err" == *"Requested --target wsl but this machine is linux"* ]] || {
  printf 'unexpected message: %s\n' "$err" >&2
  exit 1
}

# require_supported_ubuntu
OS_RELEASE_FILE="$FX/os-release/ubuntu-26.04" in_env require_supported_ubuntu
if OS_RELEASE_FILE="$FX/os-release/ubuntu-24.04" in_env require_supported_ubuntu >/dev/null 2>&1; then
  echo "Ubuntu 24.04 must be refused" >&2
  exit 1
fi
err="$(OS_RELEASE_FILE="$FX/os-release/ubuntu-24.04" in_env require_supported_ubuntu 2>&1 || true)"
[[ "$err" == *24.04* ]] || {
  printf 'message lacks 24.04: %s\n' "$err" >&2
  exit 1
}
err="$(OS_RELEASE_FILE="$FX/os-release/debian-13" in_env require_supported_ubuntu 2>&1 || true)"
[[ "$err" == *debian* ]] || {
  printf 'message lacks debian: %s\n' "$err" >&2
  exit 1
}
if OS_RELEASE_FILE="$FX/os-release/debian-13" in_env require_supported_ubuntu >/dev/null 2>&1; then
  echo "Debian 13 must be refused" >&2
  exit 1
fi

# require_x86_64
UNAME_M=x86_64 in_env require_x86_64
if UNAME_M=aarch64 in_env require_x86_64 >/dev/null 2>&1; then
  echo "aarch64 must be refused" >&2
  exit 1
fi

# require_not_root: is_root is the stub point, EUID is readonly.
(
  source "$ROOT/script/lib/common.sh"
  is_root() { return 0; }
  err="$( (require_not_root) 2>&1 || true)"
  [[ "$err" == *"Run as your normal user; the scripts call sudo themselves."* ]] || {
    printf 'unexpected message: %s\n' "$err" >&2
    exit 1
  }
  if (require_not_root) >/dev/null 2>&1; then
    echo "root must be refused" >&2
    exit 1
  fi
  is_root() { return 1; }
  require_not_root
)

# repos_under_mnt: only .git directories to depth 4 under MNT_ROOT/*.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/c/a/.git" "$tmp/c/a1/b2/c3/d4/e5/.git"
got="$(MNT_ROOT="$tmp" in_env repos_under_mnt)"
expect_eq "$got" "$tmp/c/a/.git"

# The companion Windows host repository is exempt by its origin, with or without .git;
# a look-alike name and a repo with no origin still count.
for url in https://github.com/istvano/setup-dev-win.git https://github.com/istvano/setup-dev-win; do
  rm -rf "$tmp/c"
  git init -q "$tmp/c/install/setup-dev-win"
  git -C "$tmp/c/install/setup-dev-win" remote add origin "$url"
  got="$(MNT_ROOT="$tmp" in_env repos_under_mnt)"
  expect_eq "$got" ""
done
git init -q "$tmp/c/src/other"
git -C "$tmp/c/src/other" remote add origin https://github.com/istvano/setup-dev-win-fork.git
git init -q "$tmp/c/src/bare"
got="$(MNT_ROOT="$tmp" in_env repos_under_mnt | sort)"
expect_eq "$got" "$(printf '%s\n%s' "$tmp/c/src/bare/.git" "$tmp/c/src/other/.git")"

echo 'platform tests passed.'
