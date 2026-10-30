#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/install-oh-my-zsh.sh"

plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-tab"
if [[ -d "$plugin_dir/.git" ]]; then
  git -C "$plugin_dir" pull --ff-only
else
  mkdir -p "$(dirname "$plugin_dir")"
  git clone https://github.com/Aloxaf/fzf-tab "$plugin_dir"
fi
