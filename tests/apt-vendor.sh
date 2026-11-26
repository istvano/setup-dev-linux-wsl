#!/usr/bin/env bash
# script/apt-vendor and the vendor repository catalogue. Behaviour runs against fakes
# (sudo, apt-get, gpg, dpkg-query) on PATH and a temporary /etc/apt, so it needs
# neither root nor Debian. Only the committed-key fingerprint test needs a real gpg.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

# The fingerprints are written out here, independently of apt/vendor.list, so editing
# a key file or the catalogue alone cannot make the test agree with itself.
declare -A FPR=(
  [docker]=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
  [microsoft]=BC528686B50D79E339D3721CEB3E94ADBE1229CF
  ["google-cloud"]=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
  ["nvidia-container-toolkit"]=C95B321B61E88C1809C4F759DDCAE044F796ECB0
  [anthropic]=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
)
LIST="$ROOT/apt/vendor.list"
SCRIPT="$ROOT/script/apt-vendor"

[[ -f "$LIST" ]] || fail "Missing apt/vendor.list"
[[ -x "$SCRIPT" ]] || fail "script/apt-vendor is missing or not executable"

# --- Static: the catalogue.
ids=()
while IFS= read -r line; do
  [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
  IFS=$' \t' read -r id profile target uri suite comps key fpr packages extra <<<"$line"
  [[ -n "$packages" && -z "$extra" ]] || fail "apt/vendor.list needs exactly nine columns: $line"
  [[ "$id" =~ ^[a-z0-9-]+$ && "$profile" =~ ^[a-z0-9-]+$ ]] || fail "Bad id or profile: $line"
  [[ "$target" == both || "$target" == linux || "$target" == wsl ]] || fail "Bad target: $line"
  [[ "$uri" == https://* && "$uri" != */ ]] || fail "uri must be https without a trailing slash: $line"
  [[ "$suite" =~ ^(@codename|/|[a-z0-9._-]+)$ ]] || fail "Bad suite: $line"
  [[ ("$suite" == / && "$comps" == -) || ("$suite" != / && "$comps" != -) ]] ||
    fail "A flat repository (suite /) has no components, any other has some: $line"
  [[ "${FPR[$key]:-}" == "$fpr" ]] || fail "apt/vendor.list fingerprint for key $key is not the expected constant"
  [[ -f "$ROOT/apt/keys/$key.asc" ]] || fail "Missing apt/keys/$key.asc"
  ids+=("$id")
done <"$LIST"
for id in docker azure-cli google-cloud-cli nvidia-container-toolkit anthropic; do
  [[ " ${ids[*]} " == *" $id "* ]] || fail "apt/vendor.list has no repository $id"
done
[[ "${#ids[@]}" -eq 5 ]] || fail "apt/vendor.list should list exactly five repositories, has ${#ids[@]}"

# No trust shortcuts, no keys from the network at install time, no download-and-run.
refute_match 'apt-key|trusted=yes|allow-insecure|curl|wget|\| *(ba)?sh' "$SCRIPT"
refute_match 'apt-key|trusted=yes' "$LIST"

# --- Committed keys: each fingerprint equals the constant (real gpg).
if command -v gpg >/dev/null 2>&1; then
  for key in "${!FPR[@]}"; do
    got="$(gpg --show-keys --with-colons "$ROOT/apt/keys/$key.asc" | awk -F: '/^pub/{p=1} p&&/^fpr/{print $10; exit}')"
    [[ "$got" == "${FPR[$key]}" ]] || fail "apt/keys/$key.asc fingerprint is $got, expected ${FPR[$key]}"
  done
elif [[ "${REQUIRE_LINTERS:-0}" == 1 ]]; then
  fail "gpg is missing and REQUIRE_LINTERS=1: cannot check the committed key fingerprints"
else
  echo 'SKIP: gpg not found; committed key fingerprints not checked'
fi

# --- Behaviour, against fakes.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"

# sudo: log the call, then run it (the temporary directories are writable).
cat >"$bin/sudo" <<'FAKE'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$FAKE_LOG"
exec "$@"
FAKE
# apt-get: log; an install marks its packages installed for the fake dpkg-query.
cat >"$bin/apt-get" <<'FAKE'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$FAKE_LOG"
if [[ "${1:-}" == install ]]; then
  shift
  for arg in "$@"; do [[ "$arg" == -* ]] || printf '%s\n' "$arg" >>"$FAKE_INSTALLED"; done
fi
FAKE
# gpg --show-keys --with-colons FILE: the "key" is its own fingerprint, so a test makes
# a mismatch by editing the file. A subkey fingerprint follows, which must be ignored.
cat >"$bin/gpg" <<'FAKE'
#!/usr/bin/env bash
file="${*: -1}"
printf 'pub:-:4096:1:ABCDEF:1::-:::scESC::::::23::0:\nfpr:::::::::%s:\nsub:-:4096:1:123456:1::::::e::::::23:\nfpr:::::::::0000000000000000000000000000000000000000:\n' "$(tr -d '[:space:]' <"$file")"
FAKE
cat >"$bin/dpkg-query" <<'FAKE'
#!/usr/bin/env bash
pkg="${*: -1}"
if grep -qx -- "$pkg" "$FAKE_INSTALLED" 2>/dev/null; then printf 'install ok installed'; else exit 1; fi
FAKE
chmod +x "$bin"/*

fresh() {
  rm -rf "${tmp:?}/root" "$tmp/fake.log" "$tmp/installed"
  mkdir -p "$tmp/root/sources.list.d" "$tmp/root/keys-src"
  : >"$tmp/fake.log"
  : >"$tmp/installed"
  printf 'ID=ubuntu\nVERSION_ID="26.04"\nVERSION_CODENAME=resolute\n' >"$tmp/root/os-release"
  for key in "${!FPR[@]}"; do printf '%s\n' "${FPR[$key]}" >"$tmp/root/keys-src/$key.asc"; done
}
run_vendor() {
  STATUS=0
  OUT="$(
    PATH="$bin:$PATH" FAKE_LOG="$tmp/fake.log" FAKE_INSTALLED="$tmp/installed" \
      OS_RELEASE_FILE="$tmp/root/os-release" APT_VENDOR_KEYS="$tmp/root/keys-src" \
      APT_KEYRING_DIR="$tmp/root/keyrings" APT_SOURCES_DIR="$tmp/root/sources.list.d" \
      APT_SOURCES_LIST="$tmp/root/sources.list" "$SCRIPT" "$@" 2>&1
  )" || STATUS=$?
}
sudo_calls() { grep -c . "$tmp/fake.log" || true; }
written() { find "$tmp/root/sources.list.d" "$tmp/root/keyrings" -type f 2>/dev/null | wc -l | tr -d ' '; }

# Usage errors exit 1 and change nothing.
for args in '' '--bogus' '--profiles dev' '--target linux' '--profiles dev --target mac' '--profiles --target linux'; do
  fresh
  # shellcheck disable=SC2086  # deliberate split of the argument string
  run_vendor $args
  [[ "$STATUS" -eq 1 ]] || fail "apt-vendor '$args' should exit 1, got $STATUS"
  [[ "$(sudo_calls)" -eq 0 ]] || fail "apt-vendor '$args' must not call sudo"
done

# Profiles with no vendor repository: nothing to do, nothing touched.
fresh
run_vendor --profiles core,dev --target linux
[[ "$STATUS" -eq 0 && "$(sudo_calls)" -eq 0 && "$(written)" -eq 0 ]] || fail "no vendor profile selected should do nothing: $OUT"

# docker on linux: the rendered source, the keyring, then update and install.
fresh
run_vendor --profiles core,runtime-docker --target linux
[[ "$STATUS" -eq 0 ]] || fail "docker install failed ($STATUS): $OUT"
src="$tmp/root/sources.list.d/docker.sources"
[[ -f "$src" ]] || fail "docker.sources was not written"
for expected in 'Types: deb' 'URIs: https://download.docker.com/linux/ubuntu' 'Suites: resolute' \
  'Components: stable' "Signed-By: $tmp/root/keyrings/docker.asc"; do
  grep -qxF -- "$expected" "$src" || fail "docker.sources lacks the line: $expected"$'\n'"$(cat "$src")"
done
cmp -s "$tmp/root/keys-src/docker.asc" "$tmp/root/keyrings/docker.asc" || fail "the docker key was not installed"
[[ "$(sed -n 1p "$src")" == '# Managed by'* ]] || fail "docker.sources lacks the managed-by header"
grep -qx 'apt-get update' "$tmp/fake.log" || grep -q 'apt-get update' "$tmp/fake.log" || fail "apt-get update was not run"
grep -q 'apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin' "$tmp/fake.log" ||
  fail "docker packages were not installed: $(cat "$tmp/fake.log")"
refute_match 'cloud-sdk|nvidia|resolute stable' "$tmp/root/sources.list.d"

# Idempotent: a second run writes and installs nothing.
: >"$tmp/fake.log"
run_vendor --profiles core,runtime-docker --target linux
[[ "$STATUS" -eq 0 ]] || fail "second run failed: $OUT"
[[ "$(sudo_calls)" -eq 0 ]] || fail "second run should not call sudo: $(cat "$tmp/fake.log")"
run_vendor --profiles core,runtime-docker --target linux --check
[[ "$STATUS" -eq 0 ]] || fail "--check after install should pass: $OUT"

# Only the selected profiles and the current target are written.
fresh
run_vendor --profiles cloud-azure,cloud-gcp,ai-agents --target wsl
[[ "$STATUS" -eq 0 ]] || fail "wsl run failed: $OUT"
for id in azure-cli google-cloud-cli anthropic; do
  [[ -f "$tmp/root/sources.list.d/$id.sources" ]] || fail "$id.sources missing"
done
[[ ! -e "$tmp/root/sources.list.d/docker.sources" && ! -e "$tmp/root/sources.list.d/nvidia-container-toolkit.sources" ]] ||
  fail "unselected repositories were written"
grep -qxF 'Suites: resolute' "$tmp/root/sources.list.d/azure-cli.sources" || fail "azure-cli should use the codename suite"
grep -qxF 'Suites: cloud-sdk' "$tmp/root/sources.list.d/google-cloud-cli.sources" || fail "gcloud suite is literal"
grep -qxF 'Suites: stable' "$tmp/root/sources.list.d/anthropic.sources" || fail "anthropic suite is literal"
# One keyring per vendor, named by key: the host can reuse the anthropic one.
[[ -f "$tmp/root/keyrings/anthropic.asc" && -f "$tmp/root/keyrings/google-cloud.asc" && -f "$tmp/root/keyrings/microsoft.asc" ]] ||
  fail "keyrings are named by vendor key"
# A linux-only repository is skipped on wsl even when its profile is selected.
run_vendor --profiles runtime-docker --target wsl
[[ "$STATUS" -eq 0 && ! -e "$tmp/root/sources.list.d/docker.sources" ]] || fail "docker must not be written on wsl: $OUT"

# A flat repository: Suites "/" and no Components line.
fresh
run_vendor --profiles gpu-nvidia --target linux
[[ "$STATUS" -eq 0 ]] || fail "nvidia run failed: $OUT"
src="$tmp/root/sources.list.d/nvidia-container-toolkit.sources"
grep -qxF 'URIs: https://nvidia.github.io/libnvidia-container/stable/deb/amd64' "$src" || fail "nvidia URI wrong"
grep -qxF 'Suites: /' "$src" || fail "a flat repository has Suites: /"
refute_match '^Components:' "$src"

# A key that is not the committed fingerprint is refused before anything is written.
fresh
printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' >"$tmp/root/keys-src/docker.asc"
run_vendor --profiles runtime-docker,cloud-azure --target linux
[[ "$STATUS" -ne 0 ]] || fail "a wrong fingerprint should fail"
[[ "$OUT" == *docker* && "$OUT" == *ingerprint* ]] || fail "the message should name the key and the fingerprint: $OUT"
[[ "$(written)" -eq 0 && "$(sudo_calls)" -eq 0 ]] || fail "nothing may be written before the fingerprint passes (azure-cli's key was fine, docker's was not)"

# An existing source for the same URI with another Signed-By stops the run, naming the
# file, before any write: APT refuses every source when one URI has two Signed-By values.
fresh
printf 'deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu resolute stable\n' \
  >"$tmp/root/sources.list.d/docker-vendor.list"
run_vendor --profiles runtime-docker --target linux
[[ "$STATUS" -ne 0 ]] || fail "a conflicting .list source should fail"
[[ "$OUT" == *docker-vendor.list* ]] || fail "the message should name the conflicting file: $OUT"
[[ "$(written)" -eq 1 && "$(sudo_calls)" -eq 0 ]] || fail "nothing may be written on a conflict"

fresh
printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: resolute\nComponents: main\nSigned-By: /etc/apt/keyrings/microsoft.gpg\n' \
  >"$tmp/root/sources.list.d/microsoft-azure.sources"
run_vendor --profiles cloud-azure --target linux
[[ "$STATUS" -ne 0 && "$OUT" == *microsoft-azure.sources* && "$(sudo_calls)" -eq 0 ]] ||
  fail "a conflicting deb822 source (trailing slash) should stop the run naming its file: $OUT"

# The same URI in a legacy sources.list with no signed-by also conflicts.
fresh
printf 'deb https://downloads.claude.ai/claude-code/apt/stable stable main\n' >"$tmp/root/sources.list"
run_vendor --profiles ai-agents --target linux
[[ "$STATUS" -ne 0 && "$OUT" == *sources.list* && "$(sudo_calls)" -eq 0 ]] || fail "a conflicting sources.list entry should stop the run: $OUT"

# The same URI with the same Signed-By in another file does not conflict.
fresh
mkdir -p "$tmp/root/keyrings"
printf 'deb [signed-by=%s] https://downloads.claude.ai/claude-code/apt/stable stable main\n' "$tmp/root/keyrings/anthropic.asc" \
  >"$tmp/root/sources.list.d/claude-code.list"
run_vendor --profiles ai-agents --target linux
[[ "$STATUS" -eq 0 ]] || fail "the same Signed-By should not conflict: $OUT"

# An unmanaged file at our own path with another Signed-By is a conflict too (it is
# the vendor's own instruction file, not ours to overwrite); our own managed file is.
fresh
printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: resolute\nComponents: stable\nSigned-By: /usr/share/keyrings/docker.asc\n' \
  >"$tmp/root/sources.list.d/docker.sources"
run_vendor --profiles runtime-docker --target linux
[[ "$STATUS" -ne 0 && "$OUT" == *docker.sources* && "$(sudo_calls)" -eq 0 ]] || fail "an unmanaged docker.sources with another keyring should stop the run: $OUT"
fresh
run_vendor --profiles runtime-docker --target linux
sed -i.bak 's/^Suites: .*/Suites: noble/' "$tmp/root/sources.list.d/docker.sources"
rm -f "$tmp/root/sources.list.d/docker.sources.bak"
run_vendor --profiles runtime-docker --target linux
[[ "$STATUS" -eq 0 ]] || fail "a drifted managed source should be rewritten: $OUT"
grep -qxF 'Suites: resolute' "$tmp/root/sources.list.d/docker.sources" || fail "the managed source was not rewritten"

# --check: reports missing packages and drift, exits 1, never calls sudo or gpg.
fresh
run_vendor --profiles runtime-docker,ai-agents --target linux --check
[[ "$STATUS" -eq 1 ]] || fail "--check on a bare machine should exit 1, got $STATUS"
[[ "$OUT" == *docker-ce* && "$OUT" == *claude-code* ]] || fail "--check should list the missing packages: $OUT"
[[ "$OUT" == *docker.sources* ]] || fail "--check should report the missing source: $OUT"
[[ "$(sudo_calls)" -eq 0 && "$(written)" -eq 0 ]] || fail "--check must not call sudo or write"
# A selected profile on the wrong target is not demanded.
run_vendor --profiles runtime-docker --target wsl --check
[[ "$STATUS" -eq 0 ]] || fail "--check must not demand a repository for another target: $OUT"

echo 'apt-vendor tests passed.'
