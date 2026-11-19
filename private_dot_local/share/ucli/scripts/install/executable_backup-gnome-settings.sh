#!/usr/bin/env bash
# Backup GNOME Shell settings and extensions for restore after reinstall.
#
# Usage: backup-gnome-settings.sh [output-dir]
#
# Default output: ~/.local/share/ucli/settings/gnome/  (chezmoi-managed)
#
# Backs up:
#   - dconf settings: /org/gnome/desktop/, /org/gnome/shell/, /org/gnome/shell/extensions/
#   - Enabled extensions list: gnome-extensions list --enabled
#   - Extension preferences (dconf per-extension schemas)
#
# ArchWiki references:
#   - https://wiki.archlinux.org/title/Dconf (dconf backup/restore)
#   - https://wiki.archlinux.org/title/GNOME (GNOME settings storage)
#   - https://wiki.archlinux.org/title/GNOME/Shell_extensions (extensions management)
set -euo pipefail

output_dir="${1:-$HOME/.local/share/ucli/settings/gnome}"

if ! command -v dconf >/dev/null 2>&1; then
  echo "missing required command: dconf (package: dconf)" >&2
  exit 1
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
  # The `gnome-extensions` CLI ships inside gnome-shell itself (usr/share/man/
  # man1/gnome-extensions.1.gz), not in gnome-shell-extensions.
  echo "missing required command: gnome-extensions (part of gnome-shell)" >&2
  exit 1
fi

mkdir -p "$output_dir"

echo "Backing up GNOME settings to: $output_dir"

# save <file> <cmd…> — write the command's output to <file> only when it
# succeeds. Redirecting straight into the file truncated it first, so a failing
# dconf (no session bus over ssh, say) used to blank a good backup silently.
failed=()
save() {
  local file="$output_dir/$1" tmp
  shift
  tmp="$(mktemp "$file.XXXXXX")"
  if "$@" >"$tmp" 2>/dev/null; then
    mv -f -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
    failed+=("${file##*/}")
  fi
}

# --- dconf settings ---
save desktop.dconf dconf dump /org/gnome/desktop/
save shell.dconf dconf dump /org/gnome/shell/
save extensions.dconf dconf dump /org/gnome/shell/extensions/

# --- extensions: enabled, and everything installed ---
save enabled-extensions.txt gnome-extensions list --enabled
save installed-extensions.txt gnome-extensions list

if ((${#failed[@]})); then
  echo "Backup incomplete — kept the previous copy of: ${failed[*]}" >&2
  echo "  (dconf and gnome-extensions need the desktop session: run this from it, not over ssh)" >&2
  exit 1
fi

echo "Backup complete."
echo "  dconf:     $output_dir/desktop.dconf, shell.dconf, extensions.dconf"
echo "  enabled:   $output_dir/enabled-extensions.txt"
echo "  installed: $output_dir/installed-extensions.txt"
echo ""
# The default directory is a chezmoi target: the next `chezmoi apply` puts the
# repo's copy back unless the new one is added to the source.
if [[ -z "${1:-}" ]] && command -v chezmoi >/dev/null 2>&1; then
  echo "Keep it in the dotfiles repo (or the next chezmoi apply reverts it):"
  echo "  chezmoi re-add $output_dir"
  echo ""
fi
echo "To restore: ucli restore-gnome-settings"
