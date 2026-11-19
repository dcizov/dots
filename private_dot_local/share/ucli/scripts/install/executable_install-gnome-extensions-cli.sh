#!/usr/bin/env bash
set -euo pipefail

# Install gnome-extensions-cli (gext) via pipx.
#
# gnome-extensions-cli is a PyPI package (not in Arch repos) that provides
# a clean CLI for managing GNOME Shell extensions:
#   gext install <uuid|pk>   install an extension
#   gext enable <uuid>       enable an extension
#   gext disable <uuid>      disable an extension
#   gext update              update all extensions
#   gext list                list installed extensions
#
# Source: https://github.com/essembeh/gnome-extensions-cli

# pipx puts its apps in ~/.local/bin, which a fresh login may not have on PATH
# yet. Add it unconditionally: checking for ~/.local/bin/pipx (as this used to)
# missed the normal case of Arch's /usr/bin/pipx, and a successful install then
# ended in "gext not found".
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v pipx >/dev/null 2>&1; then
  echo "pipx not found; install it first, then re-run this:" >&2
  echo "  sudo pacman -S --needed python-pipx" >&2
  exit 1
fi

if command -v gext >/dev/null 2>&1 || command -v gnome-extensions-cli >/dev/null 2>&1; then
  echo "gnome-extensions-cli already installed"
  exit 0
fi

echo "Installing gnome-extensions-cli via pipx ..."
pipx install gnome-extensions-cli

if command -v gext >/dev/null 2>&1; then
  echo "gnome-extensions-cli (gext) installed successfully"
  gext --version
else
  echo "warning: gext not found on PATH after install"
  echo "  add ~/.local/bin to your PATH or re-login"
  exit 1
fi