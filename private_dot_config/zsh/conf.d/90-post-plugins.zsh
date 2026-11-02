# Late shell tweaks. The plugins themselves are loaded by oh-my-zsh (see the
# `plugins=(...)` array in ~/.zshrc) from $ZSH_CUSTOM/plugins, so nothing is
# sourced here any more.
#
# This file used to source zsh-autosuggestions / zsh-syntax-highlighting from
# /usr/share/zsh/plugins — the Arch layout. The dev box has no such directory
# (provision-dev.sh clones them into $ZSH_CUSTOM/plugins instead), so the box
# silently ran without them for months: 38 zle widgets there against 70 on the
# host. Without their zle-line-pre-redraw hooks a one-row misdraw is never
# repaired, which is why a prompt redraw could eat a line on Tab in the box only.

# history-substring-search ships no key bindings of its own.
zmodload zsh/terminfo 2>/dev/null
if (( $+widgets[history-substring-search-up] )); then
  [[ -n "${terminfo[kcuu1]}" ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up || bindkey $'\e[A' history-substring-search-up
  bindkey '^P' history-substring-search-up
fi
if (( $+widgets[history-substring-search-down] )); then
  [[ -n "${terminfo[kcud1]}" ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down || bindkey $'\e[B' history-substring-search-down
  bindkey '^N' history-substring-search-down
fi

# Arch only.
[[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]] && \
  source /usr/share/doc/pkgfile/command-not-found.zsh

# ─── zsh-syntax-highlighting: the stock look, in the palette's colours ─────
#
# The plugin ships 44 roles whose defaults name ANSI colours — `fg=red`,
# `fg=green`, `fg=blue`, `fg=magenta`, `fg=yellow`, `fg=cyan`, `fg=black` for
# comments. Redefining those roles by hand drifts from upstream and changes
# the look, so instead keep every default and rewrite only the colour names
# to the palette from pre-omz.zsh: red stays red, it is just *our* red.
#
# Runs here because this file is sourced after oh-my-zsh has loaded the
# plugin, so the defaults are already in place. Idempotent: once rewritten
# the values hold hex, and no colour name matches any more.
if (( ${+ZSH_HIGHLIGHT_STYLES} )); then
  typeset -A _lam_ansi=(
    red     "${_lam[red]}"      # unknown tokens, bracket errors
    green   "${_lam[green]}"    # aliases, builtins, commands, autodirectories
    yellow  "${_lam[yellow]}"   # quoted strings, reserved words, redirections
    blue    "${_lam[cyan]}"     # globbing, history expansion, bracket level 1
    magenta "${_lam[purple]}"   # substitution delimiters, bracket level 3
    cyan    "${_lam[teal]}"     # $-quoted, global aliases, bracket level 5
    white   "${_lam[text]}"
    default "${_lam[text]}"
    # One deliberate exception: upstream paints comments `fg=black`, and this
    # palette's black slot IS the background — that would erase them. Bright
    # black is the grey the prompt and all three terminals already use.
    black   "${_lam[dim]}"
  )
  for _k in ${(k)ZSH_HIGHLIGHT_STYLES}; do
    _v=$ZSH_HIGHLIGHT_STYLES[$_k]
    for _c in ${(k)_lam_ansi}; do
      _v=${_v//fg=$_c/fg=$_lam_ansi[$_c]}
      _v=${_v//bg=$_c/bg=$_lam_ansi[$_c]}
    done
    ZSH_HIGHLIGHT_STYLES[$_k]=$_v
  done
  unset _k _v _c _lam_ansi
fi
