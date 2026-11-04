#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# Pass real_home to oh-my-zsh installer via env so it uses the right home.
export UCLI_REAL_HOME="$real_home"

# The shell tier owns its prerequisites: zsh (the omz installer needs it),
# git (plugins are cloned) and curl (omz is fetched). `ucli cli` therefore works
# on a machine that never ran `ucli setup-system`.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" shell-deps
fi

for cmd in zsh git curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: '$cmd' is missing; run: ucli cli (or install it manually)" >&2
    exit 1
  fi
done

"$script_dir/install-oh-my-zsh.sh"

# All zsh plugins go to ONE place, $ZSH_CUSTOM/plugins, on the host and in the
# dev box alike (provision-dev.sh clones the same list). oh-my-zsh loads them
# from there through plugins=(...) in ~/.zshrc. Every one of these repositories
# ships <name>/<name>.plugin.zsh, which is what oh-my-zsh's loader looks for.
plugin_root="${ZSH_CUSTOM:-$real_home/.oh-my-zsh/custom}/plugins"
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

# Set zsh as the default login shell so a fresh shell after chezmoi apply
# runs zsh with the deployed ~/.zshrc and PATH from 00-env.zsh.
if command -v chsh >/dev/null 2>&1; then
  current_shell="$(getent passwd "$real_user" | cut -d: -f7 2>/dev/null || true)"
  zsh_path="$(command -v zsh)"
  if [[ -n "$current_shell" && "$current_shell" != "$zsh_path" ]]; then
    echo "Setting zsh as default shell for $real_user ..."
    chsh -s "$zsh_path" "$real_user" 2>/dev/null || \
      echo "warning: chsh failed; run 'chsh -s $(command -v zsh)' manually" >&2
  fi
fi

# The "ucli layer" on top of stock zsh (aliases, functions, fzf, prompt) is
# chezmoi's: ~/.config/zsh/conf.d/*.zsh, pre-omz.zsh and ~/.config/starship.toml.
if [[ ! -d "$real_home/.config/zsh/conf.d" ]]; then
  echo "warning: ~/.config/zsh/conf.d not found — run 'ucli chezmoi-apply' to deploy the ucli shell layer" >&2
fi