# Completion / fzf-tab styles loaded before compinit.

# ucli recipe completion (config/zsh/completions/_ucli)
fpath=("$HOME/.config/zsh/completions" $fpath)

zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
[[ -n "$LS_COLORS" ]] && zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# fzf-tab does not follow FZF_DEFAULT_OPTS by default; keep plugin flags small.
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=auto --group-directories-first $realpath 2>/dev/null || ls -1 $realpath'
zstyle ':fzf-tab:complete:z:*' fzf-preview 'eza -1 --color=always --icons=auto --group-directories-first $realpath 2>/dev/null || ls -1 $realpath'
zstyle ':completion:*:git-checkout:*' sort false

# Command completion preview: prefer tldr, then man, then which.
zstyle ':fzf-tab:complete:-command-:*' fzf-preview \
  '(tldr --color always "$word" 2>/dev/null || man "$word" 2>/dev/null | col -bx | bat --language=man --plain --color=always || which "$word" 2>/dev/null)'
