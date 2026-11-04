# Tool shell integrations.
#
# Same flag scheme as 20-aliases.zsh: 0 turns one integration off, 1 or unset
# keeps it on. Set overrides in ~/.config/zsh/local.zsh (sourced before conf.d).
# Integrations are what actually change shell behaviour (history engine, cd,
# per-project runtimes), so this is the first thing to check when one of them
# misbehaves:

: "${UCLI_SHELL_ENABLE_ATUIN:=1}"
: "${UCLI_SHELL_ENABLE_DIRENV:=1}"
: "${UCLI_SHELL_ENABLE_ZOXIDE:=1}"
: "${UCLI_SHELL_ENABLE_MISE:=1}"

if [[ "$UCLI_SHELL_ENABLE_ATUIN" == 1 ]] && (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

if [[ "$UCLI_SHELL_ENABLE_DIRENV" == 1 ]] && (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi

if [[ "$UCLI_SHELL_ENABLE_ZOXIDE" == 1 ]] && (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

if [[ "$UCLI_SHELL_ENABLE_MISE" == 1 ]] && (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

# Inside a container, hand unknown commands to the host. Unconditional: it only
# exists to make the dev box feel like the host.
if [[ -e /run/.containerenv || -e /.dockerenv ]]; then
  command_not_found_handler() { distrobox-host-exec "$@" }
fi
