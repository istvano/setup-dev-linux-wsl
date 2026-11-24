# Terminal coding agents, run on the host (OpenAI Codex comes from mise: ADR-009)
# because they need the project checkout and the user's own credentials.
brew "opencode"   # Provider-agnostic terminal coding agent; MIT.
# Language runtimes come from mise, not Homebrew (see chezmoi mise config).
brew "shellcheck" # Native static analysis for frequently edited shell scripts.
brew "shfmt"      # Deterministic formatter for repository shell scripts.
brew "actionlint" # Native static validation for local GitHub Actions editing.
brew "yamllint"   # Local YAML syntax and style validation for repository work.
# Linting a Dockerfile and scanning an image or manifest are part of authoring
# for a container-first workstation, so they sit with the other validators.
brew "hadolint"   # Dockerfile linter, used while authoring project images.
brew "trivy"      # Scans images, filesystems and IaC for vulnerabilities and misconfiguration.
