#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Discovery is centralised in script/shell-files so this check, tests/format.sh
# and CI can never lint different sets of files.
FILES=()
while IFS= read -r file; do FILES+=("$file"); done \
  < <("$ROOT/script/shell-files")

for file in "${FILES[@]}"; do
  bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${FILES[@]}"
  echo "Shell syntax and shellcheck: OK (${#FILES[@]} files)"
elif [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
  echo 'shellcheck is required when REQUIRE_LINTERS=1.' >&2
  exit 1
else
  echo "Shell syntax: OK (${#FILES[@]} files); shellcheck not installed, skipped"
fi

# zsh scripts are user tools under chezmoi; shellcheck cannot parse zsh, so they get
# `zsh -n`. There are none until the dotfiles port, so a non-zero exit from the
# selector is tolerated here, but only its documented "none found" status (1).
ZSH_FILES=()
zsh_status=0
zsh_list="$("$ROOT/script/shell-files" --zsh 2>/dev/null)" || zsh_status=$?
case "$zsh_status" in
  0) while IFS= read -r file; do ZSH_FILES+=("$file"); done <<<"$zsh_list" ;;
  1) ;;
  *)
    echo "script/shell-files --zsh failed with status $zsh_status." >&2
    exit 1
    ;;
esac

if command -v zsh >/dev/null 2>&1; then
  for file in "${ZSH_FILES[@]}"; do
    zsh -n "$file"
  done
  echo "zsh syntax: OK (${#ZSH_FILES[@]} files)"
elif [[ "${REQUIRE_LINTERS:-0}" == "1" ]]; then
  echo 'zsh is required when REQUIRE_LINTERS=1.' >&2
  exit 1
else
  echo "zsh syntax: zsh not installed, skipped (${#ZSH_FILES[@]} files)"
fi
