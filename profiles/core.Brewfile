# Bootstrap and configuration
brew "mise"      # Project-local runtime and tool-version manager.
brew "uv"        # Fast Python package, environment and version manager.
brew "direnv"    # Per-directory environment activation with explicit approval.
brew "chezmoi"   # Idempotent dotfile and workstation configuration manager.
# Terminal and shell
brew "starship"  # Cross-shell prompt with project and version-control context.
brew "tmux"      # Persistent terminal session multiplexer.
# The interactive shell itself is a mutually exclusive choice: shell-zsh.Brewfile
# or shell-fish.Brewfile, selected by --shell. Everything below is shell-agnostic.
# git is not here: apt provides it before Homebrew exists. No gnupg or pinentry:
# commit signing is ssh-based (ADR-005). No casks on Linux.
# Core CLI
brew "ripgrep"   # Fast recursive text and regular-expression search.
brew "fd"        # Fast, user-friendly filesystem search.
brew "fzf"       # Interactive fuzzy finder for shell workflows.
brew "bat"       # Syntax-highlighted file viewer and cat replacement.
brew "eza"       # Modern directory listing with Git metadata; also provides --tree.
brew "zoxide"    # Frecency-based directory navigation.
brew "atuin"     # Local SQLite-backed shell history with contextual search.
brew "jq"        # Command-line JSON query and transformation tool.
brew "yq"        # Command-line YAML, JSON and XML processor.
brew "git-delta" # Syntax-highlighted pager for Git diffs.
brew "btop"      # Interactive dashboard for host processes, CPU, memory, disk and network.
brew "just"      # Thin command runner for repository workflows.
# A stated exception to one-tool-per-job: curl stays for scripting, xh for
# interactive API work, which is a daily task here. Two clients, deliberately.
brew "xh"        # Ergonomic HTTP client for talking to remote APIs by hand.
brew "trash-cli" # Moves files to the freedesktop Trash instead of unlinking them.
# Model repositories use Git LFS (Hugging Face stores weights in it); cloning one
# without it silently yields pointer files instead of weights.
brew "git-lfs"   # Large-file storage, used by model repositories.
# Editing
brew "neovim"    # Terminal editor for SSH, recovery and other no-GUI sessions.
# Version control and security baseline
brew "gh"        # GitHub command-line client for repository workflows.
brew "age"       # Small file-encryption CLI retained as part of the bootstrap trust set.
brew "sops"      # Encrypts structured secret files with the age identity created at first apply.
brew "gitleaks"  # Fast native scanner for secrets in source and Git history.
