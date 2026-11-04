#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# Pass real_home to oh-my-zsh installer via env so it uses the right home.
export UCLI_REAL_HOME="$real_home"

# The shell tier installs its own tools: zsh (the omz installer needs it), git
# (plugins are cloned), curl (omz is fetched) and starship (the prompt
# 99-prompt.zsh initialises). This is why `ucli cli` works on a machine that
# never ran `ucli setup-system`.
#
# setup-desktop runs as root and installs these itself before re-running this
# script as the user, so it passes UCLI_SKIP_PACKAGES=1 to avoid a nested sudo.
if [[ "${UCLI_SKIP_PACKAGES:-0}" != "1" && -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" shell-tools
fi

for cmd in zsh git curl starship; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: '$cmd' is missing; run: ucli cli (or install it manually)" >&2
    exit 1
  fi
done

"$script_dir/install-oh-my-zsh.sh"

# All zsh plugins go to ONE place, $ZSH_CUSTOM/plugins, on the host and in the
# dev box alike. oh-my-zsh loads them from there through plugins=(...) in
# ~/.zshrc. Every one of these repositories ships <name>/<name>.plugin.zsh, which
# is what oh-my-zsh's loader looks for.
#
# WHICH plugins is not decided here: ~/.config/zsh/plugins.txt (chezmoi) is the
# single list, also read by ~/.zshrc, the chezmoi repair hook and the dev box.
plugins_file="${real_home}/.config/zsh/plugins.txt"
# zsh was just installed, and zsh existing is exactly what .chezmoiignore waits
# for before deploying the shell layer. A console box that runs `ucli cli` as its
# first ucli command therefore has the binary but not the files: deploy them here
# rather than telling the user to run chezmoi first.
if [[ ! -r "$plugins_file" ]] && command -v chezmoi >/dev/null 2>&1; then
  echo "shell config not deployed yet; running: chezmoi apply (shell layer)"
  chezmoi apply -- "$real_home/.zshrc" "$real_home/.config/zsh" "$real_home/.config/starship.toml" \
    >/dev/null 2>&1 \
    || echo "warning: 'chezmoi apply' failed; run 'ucli chezmoi-apply' to deploy the shell layer" >&2
fi
if [[ ! -r "$plugins_file" ]]; then
  echo "error: $plugins_file missing — run 'ucli chezmoi-apply' first (it ships the plugin list)" >&2
  exit 1
fi
mapfile -t plugin_repos < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$plugins_file" | grep -v '^$')
plugin_root="${ZSH_CUSTOM:-$real_home/.oh-my-zsh/custom}/plugins"
mkdir -p "$plugin_root"
for repo in "${plugin_repos[@]}"
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
if [[ ! -r "$real_home/.config/starship.toml" ]]; then
  echo "warning: ~/.config/starship.toml not found — starship will run with its default prompt (run 'ucli chezmoi-apply')" >&2
fi