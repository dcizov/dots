# Environment.

export PATH="$HOME/.local/bin:$PATH"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="less -FRX"
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"

# zoxide environment variables must be set before zoxide init.
export _ZO_ECHO=1

# Composer global binaries inside Distrobox development containers.
if [[ -f /run/.containerenv && -d "$HOME/.config/composer/vendor/bin" ]]; then
  export PATH="$HOME/.config/composer/vendor/bin:$PATH"
fi

if [[ -e /run/.containerenv || -e /.dockerenv ]]; then
  export NVM_DIR="$HOME/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  if ! command -v node >/dev/null 2>&1; then
    nvm use --lts >/dev/null 2>&1 || nvm use default >/dev/null 2>&1 || true
  fi
fi