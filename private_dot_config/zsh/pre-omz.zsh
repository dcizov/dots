# Completion / fzf-tab styles loaded before compinit, plus every colour the
# interactive shell paints. This file is sourced before oh-my-zsh, which is
# what the plugin colour variables below need — the plugins themselves are
# loaded from the `plugins=(...)` array in ~/.zshrc.
#
# ─── Palette ──────────────────────────────────────────────────────────────
# One source of truth. It mirrors the `lambda` palette in starship.toml and
# the 16 ANSI slots in ~/.config/ghostty/config, so the prompt, the syntax
# highlighting, the autosuggestion, the completion popup and fzf agree.
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

# ─── zle's own colours ────────────────────────────────────────────────────
# What completion would add, the ^R match, the selected row of the menu.
zle_highlight=(
  "default:fg=${_lam[text]}"
  "suffix:fg=${_lam[dim]}"
  "special:fg=${_lam[teal]}"
  "region:fg=${_lam[white]},bg=${_lam[surface]}"
  "isearch:fg=${_lam[bg]},bg=${_lam[yellow]}"
  "paste:fg=${_lam[white]},bg=${_lam[surface]}"
  "listselect:fg=${_lam[white]},bg=#2f4b56"
)

# ─── zsh-autosuggestions ──────────────────────────────────────────────────
# The ghost text is the dimmest thing on screen: it must never compete with
# the command you are actually typing.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${_lam[dim]}"

# ─── zsh-history-substring-search ─────────────────────────────────────────
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND="bg=${_lam[surface]},fg=${_lam[white]},bold"
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND="bg=${_lam[surface]},fg=${_lam[red]}"
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_TIMEOUT=0.2

# ucli recipe completion (config/zsh/completions/_ucli)
fpath=("$HOME/.config/zsh/completions" $fpath)

zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
[[ -n "$LS_COLORS" ]] && zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# fzf-tab does not follow FZF_DEFAULT_OPTS by default; keep plugin flags small.
# It still gets the palette explicitly: this is the Tab popup.
zstyle ':fzf-tab:*' fzf-flags --color="fg:${_lam[text]},bg:${_lam[bg]},hl:${_lam[cyan]},fg+:${_lam[white]},bg+:${_lam[surface]},hl+:${_lam[teal]},info:${_lam[dim]},prompt:${_lam[teal]},pointer:${_lam[purple]},marker:${_lam[green]},spinner:${_lam[teal]},header:${_lam[dim]},border:${_lam[border]},label:${_lam[dim]},query:${_lam[text]},disabled:${_lam[dim]}"
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=auto --group-directories-first $realpath 2>/dev/null || ls -1 $realpath'
zstyle ':fzf-tab:complete:z:*' fzf-preview 'eza -1 --color=always --icons=auto --group-directories-first $realpath 2>/dev/null || ls -1 $realpath'
zstyle ':completion:*:git-checkout:*' sort false

# Command completion preview: prefer tldr, then man, then which.
zstyle ':fzf-tab:complete:-command-:*' fzf-preview \
  '(tldr --color always "$word" 2>/dev/null || man "$word" 2>/dev/null | col -bx | bat --language=man --plain --color=always || which "$word" 2>/dev/null)'
