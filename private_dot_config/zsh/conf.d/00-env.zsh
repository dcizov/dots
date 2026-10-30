# Locale — first, because it decides how zsh measures the prompt.
#
# zsh measures a prompt in BYTES unless it is really running multibyte
# (Src/utils.c: mb_metastrlenend() returns the byte length when MB_CUR_MAX == 1).
# starship's prompt is mostly multibyte glyphs (╭ ─ … 🌱 ▸), so in that state zsh
# believes the line is ~10 columns wider than it is and zle erases a screen line
# on every redraw — Enter and Tab both scroll one line too many.
#
# Ask zsh itself rather than the environment: a locale variable naming a locale
# the container never generated makes setlocale(LC_ALL, "") fail as a whole, and
# zsh then silently stays in C while `locale charmap` can still print UTF-8.
# Counting one wide glyph answers the question that zle actually asks.
if (( ${#${(%):-🌱}} > 1 )); then
  # C.UTF-8 is built into glibc >= 2.35, so it exists on Arch and Debian 12+
  # even when locale-gen has never run.
  unset LC_ALL LC_CTYPE
  export LANG=C.UTF-8
  if (( ${#${(%):-🌱}} > 1 )); then
    print -u2 "warning: no usable UTF-8 locale; the prompt will be misaligned"
  fi
fi

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