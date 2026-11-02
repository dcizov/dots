# Completion / fzf-tab styles loaded before compinit, plus the palette the
# shell colours itself from. Sourced before oh-my-zsh (the plugins themselves
# come from the `plugins=(...)` array in ~/.zshrc).
#
# ─── Palette ──────────────────────────────────────────────────────────────
# One source of truth. It mirrors the `lambda` palette in starship.toml and
# the 16 ANSI slots in ~/.config/ghostty/themes/Lambda (kitty and konsole use
# the same 16). Only zsh-syntax-highlighting needs it in the shell: it paints
# with hex, not with ANSI names.
typeset -gA _lam=(
  bg      '#222e34'   # window background
  surface '#2b3940'   # current line in fzf, selected row in the menu
  border  '#33424a'   # fzf borders
  dim     '#5b7683'   # comments, autosuggestion ghost text, fzf info
  muted   '#77767b'   # the clock
  text    '#d5d7d9'   # ordinary text
  white   '#ffffff'   # highlighted text
  yellow  '#efd25c'   # username, warnings, globbing
  pink    '#d54f8b'   # hostname
  cyan    '#00c6dc'   # paths, parameters
  purple  '#cb75f7'   # branch names, functions, redirections
  green   '#83b64f'   # aliases, quoted strings
  teal    '#1addb3'   # builtins, the fzf prompt
  red     '#df005f'   # errors, unknown tokens
)

# Nothing below this line paints a colour on purpose.
#
# The terminal's 16 ANSI slots are these same values, so every plugin default
# that *names* a colour already renders in the palette with no config: the
# autosuggestion's `fg=8` is bright black (#5b7683), the history search's
# `bg=magenta,fg=white,bold` is #cb75f7 on #ffffff, fzf's `hl:2` / `prompt:4`
# are leaf green and path cyan. Restating them here would only be a second
# copy that can drift — the palette is changed in one place, the terminal.
#
# The single exception is zsh-syntax-highlighting's `comment = fg=black`,
# which on this background would be invisible; see 90-post-plugins.zsh.

# ucli recipe completion (config/zsh/completions/_ucli)
fpath=("$HOME/.config/zsh/completions" $fpath)

zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
[[ -n "$LS_COLORS" ]] && zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# fzf-tab does not follow FZF_DEFAULT_OPTS by default; keep plugin flags small.
# Its colours come from fzf's own ANSI-based scheme, so they follow the palette.
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=auto --group-directories-first $realpath 2>/dev/null || ls -1 $realpath'
zstyle ':fzf-tab:complete:z:*' fzf-preview 'eza -1 --color=always --icons=auto --group-directories-first $realpath 2>/dev/null || ls -1 $realpath'
zstyle ':completion:*:git-checkout:*' sort false

# Command completion preview: prefer tldr, then man, then which.
zstyle ':fzf-tab:complete:-command-:*' fzf-preview \
  '(tldr --color always "$word" 2>/dev/null || man "$word" 2>/dev/null | col -bx | bat --language=man --plain --color=always || which "$word" 2>/dev/null)'
