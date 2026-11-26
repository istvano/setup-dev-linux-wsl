#!/usr/bin/env bash
# script/docker-setup. Behaviour runs against fakes (sudo, apt-get, dpkg-query,
# systemctl, getent, usermod) on PATH and a temporary /etc/docker, so it needs neither
# root nor Debian.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}
SCRIPT="$ROOT/script/docker-setup"
[[ -x "$SCRIPT" ]] || fail "script/docker-setup is missing or not executable"

refute_match 'curl|wget|\| *(ba)?sh|--purge|\bpurge\b|docker\.sock' "$SCRIPT"
assert_match 'docker conflicts' "$ROOT/bootstrap"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"

cat >"$bin/sudo" <<'FAKE'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$FAKE_LOG"
exec "$@"
FAKE
# apt-get remove -y PKG...: forget the packages for the fake dpkg-query.
cat >"$bin/apt-get" <<'FAKE'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$FAKE_LOG"
if [[ "${1:-}" == remove ]]; then
  shift
  for arg in "$@"; do [[ "$arg" == -* ]] || sed -i.bak "/^${arg}\$/d" "$FAKE_INSTALLED"; done
fi
FAKE
cat >"$bin/dpkg-query" <<'FAKE'
#!/usr/bin/env bash
pkg="${*: -1}"
if grep -qx -- "$pkg" "$FAKE_INSTALLED" 2>/dev/null; then printf 'install ok installed'; else exit 1; fi
FAKE
# systemctl: enabled/active are marker files; enable --now sets both, restart is logged.
cat >"$bin/systemctl" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  is-enabled) [[ -e "$FAKE_STATE/enabled" ]] ;;
  is-active) [[ -e "$FAKE_STATE/active" ]] ;;
  enable) touch "$FAKE_STATE/enabled" "$FAKE_STATE/active" ;;
  restart) ;;
  *) exit 2 ;;
esac
FAKE
cat >"$bin/getent" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == group && "$2" == docker ]] || exit 2
[[ -e "$FAKE_STATE/nogroup" ]] && exit 2
printf 'docker:x:999:%s\n' "$(cat "$FAKE_STATE/members" 2>/dev/null)"
FAKE
cat >"$bin/usermod" <<'FAKE'
#!/usr/bin/env bash
# usermod -aG docker USER
printf '%s\n' "$3" >>"$FAKE_STATE/members"
FAKE
chmod +x "$bin"/*

LOG="$tmp/fake.log"
fresh() {
  rm -rf "${tmp:?}/etc" "${tmp:?}/state"
  mkdir -p "$tmp/etc" "$tmp/state"
  : >"$LOG"
  : >"$tmp/installed"
}
run() {
  STATUS=0
  OUT="$(
    PATH="$bin:$PATH" FAKE_LOG="$LOG" FAKE_INSTALLED="$tmp/installed" FAKE_STATE="$tmp/state" \
      DOCKER_DAEMON_JSON="$tmp/etc/docker/daemon.json" DOCKER_SETUP_USER=alice "$SCRIPT" "$@" 2>&1
  )" || STATUS=$?
}
sudo_calls() { grep -c '^sudo ' "$LOG" || true; }
JSON='{"log-driver": "local"}'
PROF=core,runtime-docker

# Usage errors exit 1 and change nothing.
for args in '' '--bogus' '--check' '--profiles' '--profiles --check'; do
  fresh
  # shellcheck disable=SC2086  # deliberate split of the argument string
  run $args
  [[ "$STATUS" -eq 1 && "$(sudo_calls)" -eq 0 ]] || fail "docker-setup '$args' should exit 1 without sudo, got $STATUS"
done

# Not selected: nothing runs, in every mode, even with conflicting packages installed.
fresh
printf 'docker.io\n' >"$tmp/installed"
for mode in '' --check --remove-conflicts; do
  # shellcheck disable=SC2086
  run --profiles core,dev $mode
  [[ "$STATUS" -eq 0 && "$(sudo_calls)" -eq 0 && ! -e "$tmp/etc/docker" ]] ||
    fail "runtime-docker not selected: '$mode' must do nothing: $OUT"
done

# --remove-conflicts asks apt-get to remove only the installed conflicting packages.
fresh
printf 'docker.io\nvim\n' >"$tmp/installed"
run --profiles "$PROF" --remove-conflicts
[[ "$STATUS" -eq 0 ]] || fail "--remove-conflicts failed: $OUT"
grep -qx 'sudo apt-get remove -y docker.io' "$LOG" || fail "docker.io was not removed alone: $(cat "$LOG")"
[[ "$(sudo_calls)" -eq 1 ]] || fail "--remove-conflicts made other sudo calls: $(cat "$LOG")"
[[ ! -e "$tmp/etc/docker/daemon.json" && ! -e "$tmp/state/enabled" ]] || fail "--remove-conflicts must not configure docker"
grep -qx vim "$tmp/installed" || fail "an unrelated package was removed by the fake apt-get"
: >"$LOG"
run --profiles "$PROF" --remove-conflicts
[[ "$STATUS" -eq 0 && "$(sudo_calls)" -eq 0 ]] || fail "--remove-conflicts again should do nothing: $OUT"

# --check: a conflicting package is drift, and no sudo runs.
fresh
printf 'podman-docker\n' >"$tmp/installed"
run --profiles "$PROF" --remove-conflicts --check
[[ "$STATUS" -eq 1 && "$OUT" == *podman-docker* && "$(sudo_calls)" -eq 0 ]] || fail "--remove-conflicts --check should flag podman-docker: $OUT"

# --check on an unconfigured machine names every item, with no sudo.
fresh
run --profiles "$PROF" --check
[[ "$STATUS" -eq 1 && "$(sudo_calls)" -eq 0 ]] || fail "--check on a bare machine should fail without sudo: $OUT"
for item in 'daemon.json' 'not enabled' 'not active' 'docker group'; do
  [[ "$OUT" == *"$item"* ]] || fail "--check does not report '$item': $OUT"
done

# Full apply: conflicts removed FIRST, daemon.json exact, enabled and started, group added.
fresh
printf 'docker.io\npodman-docker\n' >"$tmp/installed"
run --profiles "$PROF"
[[ "$STATUS" -eq 0 ]] || fail "apply failed ($STATUS): $OUT"
[[ "$(sed -n 1p "$LOG")" == 'sudo apt-get remove -y docker.io podman-docker' ]] || fail "conflicts must be removed first: $(cat "$LOG")"
[[ "$(cat "$tmp/etc/docker/daemon.json")" == "$JSON" ]] || fail "daemon.json content wrong: $(cat "$tmp/etc/docker/daemon.json")"
grep -qx 'sudo systemctl enable --now docker' "$LOG" || fail "docker was not enabled and started: $(cat "$LOG")"
grep -qx 'sudo usermod -aG docker alice' "$LOG" || fail "alice was not added to the docker group: $(cat "$LOG")"
[[ "$OUT" == *'next login'* && "$OUT" == *root-equivalent* ]] || fail "the group warning must say next login and root-equivalent: $OUT"
[[ -z "$(find "$tmp/etc/docker" -name 'daemon.json.backup.*')" ]] || fail "a fresh daemon.json needs no backup"
run --profiles "$PROF" --check
[[ "$STATUS" -eq 0 && "$OUT" != *drift* ]] || fail "--check after apply should pass: $OUT"

# Idempotent: a second run makes no sudo call at all.
: >"$LOG"
run --profiles "$PROF"
[[ "$STATUS" -eq 0 && "$(sudo_calls)" -eq 0 ]] || fail "second run should not call sudo: $(cat "$LOG")"

# A different daemon.json is backed up (with its content) then replaced; running dockerd restarts.
fresh
mkdir -p "$tmp/etc/docker"
printf '{"log-driver": "json-file"}\n' >"$tmp/etc/docker/daemon.json"
touch "$tmp/state/enabled" "$tmp/state/active"
printf 'alice\n' >"$tmp/state/members"
run --profiles "$PROF"
[[ "$STATUS" -eq 0 ]] || fail "replace run failed: $OUT"
[[ "$(cat "$tmp/etc/docker/daemon.json")" == "$JSON" ]] || fail "daemon.json was not replaced"
bk="$(find "$tmp/etc/docker" -name 'daemon.json.backup.*')"
[[ -n "$bk" && "$(cat "$bk")" == '{"log-driver": "json-file"}' ]] || fail "the old daemon.json was not backed up intact"
grep -qx 'sudo systemctl restart docker' "$LOG" || fail "a running dockerd must restart for the new config: $(cat "$LOG")"
refute_match 'usermod|enable --now' "$LOG"

# daemon.json that is a superset with log-driver local (nvidia-ctk adds "runtimes")
# matches: no write, no restart. Another log-driver or invalid JSON does not.
fresh
mkdir -p "$tmp/etc/docker"
printf '{"runtimes": {"nvidia": {"path": "nvidia-container-runtime"}}, "log-driver": "local"}\n' >"$tmp/etc/docker/daemon.json"
touch "$tmp/state/enabled" "$tmp/state/active"
printf 'alice\n' >"$tmp/state/members"
run --profiles "$PROF" --check
[[ "$STATUS" -eq 0 && "$OUT" != *drift* ]] || fail "a superset with log-driver local should match: $OUT"
run --profiles "$PROF"
[[ "$STATUS" -eq 0 && "$(sudo_calls)" -eq 0 ]] || fail "a superset must cause no write and no restart: $(cat "$LOG")"
grep -q nvidia "$tmp/etc/docker/daemon.json" || fail "the superset daemon.json was modified"
for bad in '{"runtimes": {}, "log-driver": "json-file"}' '{"runtimes": {}}' 'not json' '["log-driver", "local"]' ''; do
  printf '%s\n' "$bad" >"$tmp/etc/docker/daemon.json"
  run --profiles "$PROF" --check
  [[ "$STATUS" -eq 1 && "$OUT" == *daemon.json* ]] || fail "'$bad' must not match: $OUT"
done
printf 'not json\n' >"$tmp/etc/docker/daemon.json"
run --profiles "$PROF"
[[ "$(cat "$tmp/etc/docker/daemon.json")" == "$JSON" ]] || fail "invalid JSON should be replaced"
[[ -n "$(find "$tmp/etc/docker" -name 'daemon.json.backup.*')" ]] || fail "invalid JSON should be backed up first"
grep -qx 'sudo systemctl restart docker' "$LOG" || fail "replacing daemon.json must restart a running dockerd"

# The group is added only when missing, and only for this user.
fresh
printf 'bob\n' >"$tmp/state/members"
run --profiles "$PROF"
grep -qx 'sudo usermod -aG docker alice' "$LOG" || fail "alice should be added when only bob is a member"
fresh
printf 'bob,alice\n' >"$tmp/state/members"
run --profiles "$PROF"
refute_match 'usermod' "$LOG"
fresh
touch "$tmp/state/nogroup"
run --profiles "$PROF"
[[ "$STATUS" -eq 1 && "$OUT" == *apt-vendor* ]] || fail "a missing docker group should point at apt-vendor: $OUT"

# Never as root: EUID is readonly, so assert statically that the guard sits after the
# --check branch (which needs no privilege) and before the first sudo call.
guard="$(grep -n '^require_not_root$' "$SCRIPT" | cut -d: -f1)"
# shellcheck disable=SC2016  # a literal source line, not an expansion
checkend="$(grep -n -F '  exit "$drift"' "$SCRIPT" | cut -d: -f1)"
firstsudo="$(grep -n 'sudo ' "$SCRIPT" | grep -v '^[0-9]*:#' | head -n1 | cut -d: -f1)"
[[ -n "$guard" && -n "$checkend" && -n "$firstsudo" && "$checkend" -lt "$guard" && "$guard" -lt "$firstsudo" ]] ||
  fail "require_not_root must follow the --check branch and precede the first sudo call"

echo 'docker-setup tests passed.'
