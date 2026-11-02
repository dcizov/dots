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
