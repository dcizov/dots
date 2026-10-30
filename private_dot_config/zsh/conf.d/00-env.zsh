# Locale — must come first, because it changes how zsh measures the prompt.
#
# zsh counts a prompt's width in BYTES when the locale is not multibyte
# (Src/utils.c: mb_metastrlenend() returns the byte length when MB_CUR_MAX == 1).
# starship's prompt here is mostly multibyte glyphs (╭ ─ … 🌱 ▸), so in a C/POSIX
# locale zsh believes the line is ~10 columns wider than it really is; zle then
# erases and scrolls by that wrong amount on every redraw (Enter, Tab), which is
# the "prompt eats the line above it" bug inside the distrobox.
#
# The box inherits LANG from the host, but the container is a fresh Debian image
# where that locale need not be generated — glibc then silently falls back to
# ANSI_X3.4-1968 (ASCII) and the prompt breaks, while the host looks fine.
# So test the effective charset, not the name of the locale.
if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then
  # C.UTF-8 is built into glibc >= 2.35, so it exists on Arch and Debian 12+
  # without locale-gen ever having run.
  unset LC_ALL LC_CTYPE
  export LANG=C.UTF-8
  if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then
    print -u2 "warning: no UTF-8 locale available; the prompt will be misaligned"
  fi
fi

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