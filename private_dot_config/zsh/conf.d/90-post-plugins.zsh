# Manual plugins loaded late.
#
# Two possible locations, because the two systems ship them differently:
#   * Arch packages install them under /usr/share/zsh/plugins/…
#   * the dev box has no such directory — provision-dev.sh clones them into
#     oh-my-zsh's custom/plugins/, and before this file knew about that path
#     they were installed and then never loaded. That asymmetry is why the box
#     had 38 zle widgets where the host has 70: no zle-line-pre-redraw hooks,
#     so a misdraw (fzf-tab's reset-prompt on Tab) is never repaired, and the
#     prompt visibly eats a line on every Tab inside the box only.
#
# syntax-highlighting must stay LAST: it wraps the widgets that were bound
# before it loads.

_zsh_plugin() {  # <name> → prints the file to source, if any
  local name="$1" dir
  for dir in "/usr/share/zsh/plugins/$name" \
             "${ZSH:-$HOME/.oh-my-zsh}/custom/plugins/$name"; do
    [[ -r "$dir/$name.zsh" ]] && { print -r -- "$dir/$name.zsh"; return 0; }
  done
  return 1
}

for _p in zsh-autosuggestions zsh-history-substring-search; do
  _f="$(_zsh_plugin "$_p")" && source "$_f" && _ucli_loaded+=("$_p")
done
unset _p _f

zmodload zsh/terminfo 2>/dev/null
if (( $+widgets[history-substring-search-up] )); then
  [[ -n "${terminfo[kcuu1]}" ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up || bindkey $'\e[A' history-substring-search-up
  bindkey '^P' history-substring-search-up
fi
if (( $+widgets[history-substring-search-down] )); then
  [[ -n "${terminfo[kcud1]}" ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down || bindkey $'\e[B' history-substring-search-down
  bindkey '^N' history-substring-search-down
fi

[[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]] && \
  source /usr/share/doc/pkgfile/command-not-found.zsh

# Must stay close to the end.
_f="$(_zsh_plugin zsh-syntax-highlighting)" && source "$_f"
unset _f
unfunction _zsh_plugin
