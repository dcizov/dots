# fzf defaults. Keep global options generic; previews are command-specific.

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS=$'
    --height=80%
    --layout=reverse
    --border
    --info=inline
    --marker="✓ "
    --pointer="❯"
    --prompt="❯ "
    --bind=ctrl-u:preview-page-up,ctrl-d:preview-page-down
    --bind=?:toggle-preview
  '

  # Palette-matched colours; the hexes live in pre-omz.zsh.
  FZF_DEFAULT_OPTS+=" --color=fg:${_lam[text]},bg:${_lam[bg]},hl:${_lam[cyan]},fg+:${_lam[white]},bg+:${_lam[surface]},hl+:${_lam[teal]},info:${_lam[dim]},prompt:${_lam[teal]},pointer:${_lam[purple]},marker:${_lam[green]},spinner:${_lam[teal]},header:${_lam[dim]},border:${_lam[border]},label:${_lam[dim]},query:${_lam[text]},disabled:${_lam[dim]}"

  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND='fd --type f --type d --type l --strip-cwd-prefix --hidden --follow --exclude .git'
    export FZF_ALT_C_COMMAND='fd --type d --strip-cwd-prefix --hidden --follow --exclude .git'
  fi

  if (( $+commands[bat] )); then
    export FZF_CTRL_T_OPTS="
      --scheme=path
      --preview='[[ -d {} ]] && eza --tree --level=2 --color=always --icons=auto --group-directories-first {} 2>/dev/null || bat --color=always --style=numbers,changes --line-range=:300 {} 2>/dev/null || file {}'
      --preview-window=right:60%:wrap
    "
  fi

  if (( $+commands[eza] )); then
    export FZF_ALT_C_OPTS="
      --scheme=path
      --preview='eza --tree --level=2 --color=always --icons=auto --group-directories-first {} 2>/dev/null || ls -la {}'
      --preview-window=right:60%:wrap
    "
  fi
fi
