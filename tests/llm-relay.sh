#!/usr/bin/env bash
# llm-relay: argument checks, the encoded PowerShell bridge, --check outcomes and the
# socat listener it starts. Windows PowerShell and socat are replaced by fakes, so this
# runs on any host.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

RELAY="$ROOT/chezmoi/dot_local/bin/executable_llm-relay"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"

fail() {
  printf 'llm-relay test: %s\n' "$*" >&2
  exit 1
}

# A fake powershell.exe: answers like LM Studio, or refuses like a stopped server.
fake_ps() {
  local mode=$1 path="$tmp/ps-$1"
  if [[ "$mode" == ok ]]; then
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/ps-args"\ncat >/dev/null\nprintf "HTTP/1.1 200 OK\\r\\n\\r\\n{}"\n' "$tmp" >"$path"
  else
    printf '#!/usr/bin/env bash\ncat >/dev/null\necho "No connection could be made because the target machine actively refused it" >&2\nexit 1\n' >"$path"
  fi
  chmod +x "$path"
  printf '%s' "$path"
}

# --help prints the usage block.
bash "$RELAY" --help | grep -q 'llm-relay \[port\]' || fail '--help does not print the usage'

# Ports are digits in range only: the value is interpolated into a PowerShell command.
for bad in abc 0 65536 '1;calc' '12 34' -5; do
  if LLM_RELAY_POWERSHELL="$(fake_ps ok)" bash "$RELAY" --check "$bad" >/dev/null 2>&1; then
    fail "port '$bad' was accepted"
  fi
done

# Outside WSL (no powershell.exe) it refuses with a clear message.
out="$(LLM_RELAY_POWERSHELL="$tmp/missing" bash "$RELAY" --check 2>&1 || true)"
grep -q 'runs inside WSL only' <<<"$out" || fail "missing-PowerShell message: $out"

# The bridge connects to Windows localhost on the given port and silences progress.
LLM_RELAY_POWERSHELL="$(fake_ps ok)" bash "$RELAY" --check 8080 >/dev/null
enc="$(grep -A1 -- '-EncodedCommand' "$tmp/ps-args" | tail -n 1)"
decoded="$(printf '%s' "$enc" | base64 -d | iconv -f UTF-16LE -t UTF-8)"
grep -qF "TcpClient('localhost',8080)" <<<"$decoded" || fail "bridge does not target localhost:8080: $decoded"
grep -qF "\$ProgressPreference='SilentlyContinue'" <<<"$decoded" || fail 'bridge does not silence progress'
grep -q -- '-NonInteractive' "$tmp/ps-args" || fail 'PowerShell is not started non-interactively'

# --check: success prints the HTTP status and exits 0.
out="$(LLM_RELAY_POWERSHELL="$(fake_ps ok)" bash "$RELAY" --check)"
grep -q 'LM Studio answered on Windows localhost:1234: HTTP/1.1 200 OK' <<<"$out" || fail "check success output: $out"

# --check: a refused connection names the fix and exits 1.
if out="$(LLM_RELAY_POWERSHELL="$(fake_ps refused)" bash "$RELAY" --check 2>&1)"; then
  fail 'check succeeded although the connection was refused'
fi
grep -q 'Start the server in LM Studio' <<<"$out" || fail "refused output: $out"

# serve: socat listens on loopback only and hands each connection to --pump.
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/socat-args"\n' "$tmp" >"$tmp/bin/socat"
chmod +x "$tmp/bin/socat"
PATH="$tmp/bin:$PATH" LLM_RELAY_POWERSHELL="$(fake_ps ok)" bash "$RELAY" 4321 >/dev/null
grep -qx 'TCP-LISTEN:4321,bind=127.0.0.1,reuseaddr,fork' "$tmp/socat-args" || fail "socat listener: $(cat "$tmp/socat-args")"
grep -q '^EXEC:.*llm-relay --pump 4321$' "$tmp/socat-args" || fail "socat EXEC: $(cat "$tmp/socat-args")"
refute_match 'bind=0\.0\.0\.0|TCP-LISTEN:[0-9]+,fork' "$RELAY"

echo 'llm-relay tests passed.'
