#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

# Policy greps run over the paths that exist, so the test stays meaningful while
# the tree is still growing. Only the workflows directory is mandatory.
existing_paths() {
  local path
  for path in "$@"; do
    [[ -e "$path" ]] && printf '%s\n' "$path"
  done
  return 0
}

## workflows

WORKFLOWS="$ROOT/.github/workflows"
if [[ ! -d "$WORKFLOWS" ]]; then
  printf 'Missing workflows directory: %s\n' "$WORKFLOWS" >&2
  exit 1
fi

# Every `uses:` is pinned to a full commit SHA.
refute_match 'uses:[[:space:]]+[^#[:space:]]+@(v[0-9]|main|master|latest)' "$WORKFLOWS"
assert_match 'uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}' "$WORKFLOWS"

# Nothing floats.
refute_match '@latest' "$WORKFLOWS"

# Nothing is piped into a shell. tests/ is excluded so this file's own pattern
# and commentary cannot match themselves.
SCAN_PATHS=()
while IFS= read -r path; do
  SCAN_PATHS+=("$path")
done < <(existing_paths "$WORKFLOWS" "$ROOT/script" "$ROOT/bootstrap")
refute_match '(curl|wget)[^|]*\|[[:space:]]*(ba|z)?sh' "${SCAN_PATHS[@]}"

echo 'placement-policy: OK'
