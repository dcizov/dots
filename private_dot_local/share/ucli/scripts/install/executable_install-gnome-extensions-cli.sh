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

PIPX_BIN="${HOME}/.local/bin/pipx"

if ! command -v pipx >/dev/null 2>&1; then
  echo "pipx not found; installing python-pipx first ..."
  echo "  run: sudo pacman -S --needed python-pipx"
  echo "  then re-run this script"
  exit 1
fi

if command -v gext >/dev/null 2>&1 || command -v gnome-extensions-cli >/dev/null 2>&1; then
  echo "gnome-extensions-cli already installed"
  exit 0
fi

echo "Installing gnome-extensions-cli via pipx ..."
pipx install gnome-extensions-cli

# Ensure pipx binaries are on PATH
if [[ -x "${PIPX_BIN}" ]]; then
  export PATH="${HOME}/.local/bin:${PATH}"
fi

if command -v gext >/dev/null 2>&1; then
  echo "gnome-extensions-cli (gext) installed successfully"
  gext --version
else
  echo "warning: gext not found on PATH after install"
  echo "  add ~/.local/bin to your PATH or re-login"
  exit 1
fi