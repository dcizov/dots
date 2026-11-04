# Aliases.
#
# Every tool block sits behind a flag, so one machine can drop one piece without
# forking this file. All of them default to on:
#
#   UCLI_SHELL_ENABLE_EZA=0    # 0 turns the block off, 1 or unset keeps it on
#
# Set them in ~/.config/zsh/local.zsh — ~/.zshrc sources that file *before* this
# directory, so your values win over the defaults below. `ucli doctor` lists the
# flags it finds. A flag only gates the aliases: the command stays installed and
# callable by its own name.

: "${UCLI_SHELL_ENABLE_EZA:=1}"
: "${UCLI_SHELL_ENABLE_BAT:=1}"
: "${UCLI_SHELL_ENABLE_FD:=1}"
: "${UCLI_SHELL_ENABLE_RG:=1}"
: "${UCLI_SHELL_ENABLE_DUF:=1}"
: "${UCLI_SHELL_ENABLE_TLDR:=1}"
: "${UCLI_SHELL_ENABLE_GLOW:=1}"

if [[ "$UCLI_SHELL_ENABLE_EZA" == 1 ]] && (( $+commands[eza] )); then
  alias ls='eza --icons=auto --group-directories-first'
  alias l='eza --long --icons=auto --git --group-directories-first'
  alias ll='eza --long --all --header --icons=auto --git --group-directories-first --time-style=long-iso'
  alias la='eza --all --icons=auto --group-directories-first'
  alias lm='eza --long --all --header --icons=auto --git --sort=modified --reverse --group-directories-first --time-style=long-iso'
  alias lt='eza --tree --level=2 --icons=auto --git-ignore --group-directories-first'
  alias lta='eza --tree --level=2 --all --icons=auto --group-directories-first'
  alias lg='eza --long --all --header --icons=auto --git --git-ignore --group-directories-first --time-style=long-iso'
  alias tree='eza --tree --icons=auto --group-directories-first'
fi

if [[ "$UCLI_SHELL_ENABLE_BAT" == 1 ]] && (( $+commands[bat] )); then
  alias b='bat'
  alias bp='bat --paging=never'
  alias bcat='bat --paging=never --style=plain'
  alias batlangs='bat --list-languages'
  alias batthemes='bat --list-themes'
  export MANPAGER="sh -c 'col -bx | bat --language=man --plain --color=always'"
fi

if [[ "$UCLI_SHELL_ENABLE_FD" == 1 ]] && (( $+commands[fd] )); then
  alias f='fd'
  alias ff='fd --type f'
  alias fdir='fd --type d'
  alias fh='fd --hidden --exclude .git'
  alias fa='fd --hidden --no-ignore --exclude .git'
fi

if [[ "$UCLI_SHELL_ENABLE_RG" == 1 ]] && (( $+commands[rg] )); then
  alias r='rg'
  alias ri='rg --ignore-case'
  alias rs='rg --smart-case'
  alias rh='rg --hidden --glob "!.git/*"'
  alias rl='rg --files'
fi

if [[ "$UCLI_SHELL_ENABLE_DUF" == 1 ]] && (( $+commands[duf] )); then
  unalias duf 2>/dev/null
  alias df='duf'
  alias dfa='duf --all'
  alias dfi='duf --inodes'
  alias dfs='duf --sort usage'
  alias dfj='duf --json'
fi

if [[ "$UCLI_SHELL_ENABLE_TLDR" == 1 ]] && (( $+commands[tldr] )); then
  alias tl='tldr'
  alias tlu='tldr --update'
fi

# Unconditional: plain shell hygiene and Arch helpers, nothing to gate.
alias c='clear'
alias update='sudo pacman -Syu'
alias rmpkg='sudo pacman -Rns'
alias cleanch='sudo pacman -Scc'
alias fixpacman='sudo rm -f /var/lib/pacman/db.lck'
alias mk='make -j$(nproc)'
alias nj='ninja -j$(nproc)'
alias n='ninja'
alias jctl='journalctl -p 3 -xb'
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"

if [[ "$UCLI_SHELL_ENABLE_GLOW" == 1 ]] && (( $+commands[glow] )); then
  alias md='glow -p'
  alias glowp='glow -p'
fi

alias sail='[ -f sail ] && sh sail || sh vendor/bin/sail'
