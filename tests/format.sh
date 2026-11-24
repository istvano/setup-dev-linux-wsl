#!/usr/bin/env bash
# Run shfmt, actionlint and gitleaks.
#
# Set REQUIRE_LINTERS=1 (CI does) so a missing tool fails instead of silently
# skipping the check.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The extensionless scripts under script/ cannot be matched by an .editorconfig
# glob, so the flags are stated explicitly for every discovered file.
SHFMT_FLAGS=(-i 2 -ci)

missing=()

require_or_skip() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
    echo "$tool is required when REQUIRE_LINTERS=1." >&2
    exit 1
  fi
  missing+=("$tool")
  return 1
}

if require_or_skip shfmt; then
  files=()
  while IFS= read -r file; do files+=("$file"); done \
    < <("$ROOT/script/shell-files")
  shfmt -d "${SHFMT_FLAGS[@]}" "${files[@]}"
fi

# Workflows arrive with CI; with no directory there is nothing to lint, which is
# not a failure.
if [[ -d "$ROOT/.github/workflows" ]]; then
  if require_or_skip actionlint; then
    (cd "$ROOT" && actionlint)
  fi
else
  echo 'actionlint: no .github/workflows yet, nothing to lint'
fi

if require_or_skip gitleaks; then
  # Scan the working tree and the full history.
  gitleaks detect --source "$ROOT" --no-banner --redact
fi

if ((${#missing[@]} > 0)); then
  echo "Formatting and lint checks: OK (skipped: ${missing[*]})"
else
  echo 'Formatting and lint checks: OK'
fi
