# Architecture

Current state of the design. Rationale lives in `DECISIONS.md`.

## Targets

Ubuntu 26.04 LTS on x86_64, either in WSL2 (`--target wsl`) or on a headless
machine or VM (`--target linux`). Nothing else is supported.

## Layers

1. apt: a small base set, plus vendor repos with committed keys.
2. Homebrew on Linux: CLI tools, from rendered profile Brewfiles.
3. mise: language runtimes; uv for Python.
4. chezmoi: dotfiles, rooted at `chezmoi/` through `.chezmoiroot`.

## Execution boundaries

Linux host for CLI tools, project-local uv environments for Python and AI work,
containers for stateful services and scanners, an isolated VM for hostile work.

## Test harness

`script/test` requires bash 5 and runs the tests in `tests/`. Shell scripts are
found by shebang through `script/shell-files`, so every check lints the same set.
