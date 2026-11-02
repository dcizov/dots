#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/install-oh-my-zsh.sh"

# All zsh plugins go to ONE place, $ZSH_CUSTOM/plugins, on the host and in the
# dev box alike (provision-dev.sh clones the same list). oh-my-zsh loads them
# from there through plugins=(...) in ~/.zshrc. Every one of these repositories
# ships <name>/<name>.plugin.zsh, which is what oh-my-zsh's loader looks for.
plugin_root="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
mkdir -p "$plugin_root"
for repo in \
  Aloxaf/fzf-tab \
  zsh-users/zsh-autosuggestions \
  zsh-users/zsh-syntax-highlighting \
  zsh-users/zsh-history-substring-search
do
  name="${repo#*/}"
  if [[ -d "$plugin_root/$name/.git" ]]; then
    git -C "$plugin_root/$name" pull --ff-only || true
  else
    echo "cloning $name -> $plugin_root/$name"
    git clone --depth=1 "https://github.com/$repo.git" "$plugin_root/$name"
  fi
done
