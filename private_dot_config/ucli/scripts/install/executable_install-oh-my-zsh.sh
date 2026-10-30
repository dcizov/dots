#!/usr/bin/env bash
set -euo pipefail

omz_dir="${ZSH:-$HOME/.oh-my-zsh}"
[[ -d "$omz_dir/.git" && -r "$omz_dir/oh-my-zsh.sh" ]] && { echo "Oh My Zsh already installed: $omz_dir"; exit 0; }
for cmd in zsh git curl; do command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd" >&2; exit 1; }; done
CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
