# Git shortcuts, the everyday subset of oh-my-zsh's git plugin under the same names.
#
# Managed by chezmoi from chezmoi/dot_config/zsh/git-aliases.zsh and sourced by ~/.zshrc.
# fish has the same set as abbreviations in config.fish; tests/placement-policy.sh keeps the
# two identical. oh-my-zsh itself stays dropped (docs/DROPPED.md); these replace only the
# aliases the operator kept (setup-dev-linux D012). `alias` shows them all.
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gc='git commit --verbose'
alias gcmsg='git commit --message'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gd='git diff'
alias gds='git diff --staged'
alias gf='git fetch'
alias gl='git pull'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias glog='git log --oneline --decorate --graph'
alias grb='git rebase'
alias grbi='git rebase --interactive'
alias gst='git status'
alias gsta='git stash push'
alias gstp='git stash pop'
