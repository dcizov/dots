# Message of the day: a compact system summary when a login shell starts.
#
# Deliberately NOT on every new terminal. A banner on every tab is the thing
# people complain about with Bluefin's "bling", and it costs a fastfetch run per
# window. Login shells are TTY logins, SSH, `zsh -l` and tmux — the moments where
# you actually want to see which machine you landed on.
#
# Control it with:
#   ucli motd            # show the current setting
#   ucli motd on         # login shells (default)
#   ucli motd always     # every interactive shell, like bling does it
#   ucli motd off
#
# State: ${XDG_STATE_HOME:-~/.local/state}/ucli/motd. If you keep your own
# ~/.config/fastfetch/config.jsonc it is used as-is; otherwise this prints a
# logo-less summary so nothing here depends on a checked-in fastfetch config.

: "${UCLI_SHELL_ENABLE_MOTD:=1}"

if [[ "$UCLI_SHELL_ENABLE_MOTD" == 1 ]] && [[ -t 1 ]] && (( $+commands[fastfetch] )); then
  _ucli_motd_mode="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/ucli/motd" 2>/dev/null || echo on)"

  # "always" fires everywhere; anything else only in a login shell. The guard
  # variable stops a login shell that spawns another one (tmux, su, zsh -l
  # inside zsh) from printing twice.
  if [[ "$_ucli_motd_mode" != "off" ]] && [[ -z "${UCLI_MOTD_SHOWN:-}" ]] &&
     { [[ "$_ucli_motd_mode" == "always" ]] || [[ -o login ]]; }; then
    if [[ -r "$HOME/.config/fastfetch/config.jsonc" ]]; then
      fastfetch
    else
      fastfetch --logo none \
        --structure "title:separator:os:host:kernel:uptime:packages:shell:wm:de:memory" \
        2>/dev/null || true
    fi
    export UCLI_MOTD_SHOWN=1
  fi
  unset _ucli_motd_mode
fi

# Welcome once per machine. `ucli welcome --first-login` prints the status block
# (machine, pending updates, last restore point, reboot) plus the next steps the
# first time any shell runs it, commits a version gate, and says nothing on every
# later shell. That is the CachyOS-Hello first-login screen without a window.
if [[ -t 1 ]] && (( $+commands[ucli] )) && [[ -z "${UCLI_WELCOME_SHOWN:-}" ]]; then
  ucli welcome --first-login 2>/dev/null || true
  export UCLI_WELCOME_SHOWN=1
fi
