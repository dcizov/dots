# Tool shell integrations.

if (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

if [[ -e /run/.containerenv || -e /.dockerenv ]]; then
  command_not_found_handler() { distrobox-host-exec "$@" }
fi
