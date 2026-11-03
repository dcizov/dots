#!/usr/bin/env bash
# Restore GNOME Shell settings and extensions from backup.
#
# Usage: restore-gnome-settings.sh [input-dir]
#
# Default input: ~/.local/share/ucli/settings/gnome/  (chezmoi-managed)
#
# Restores:
#   - dconf settings: /org/gnome/desktop/, /org/gnome/shell/, /org/gnome/shell/extensions/
#   - Enabled extensions: reads enabled-extensions.txt and enables each
#
# ArchWiki references:
#   - https://wiki.archlinux.org/title/Dconf (dconf backup/restore)
#   - https://wiki.archlinux.org/title/GNOME (GNOME settings storage)
#   - https://wiki.archlinux.org/title/GNOME/Shell_extensions (extensions management)
set -euo pipefail

input_dir="${1:-$HOME/.local/share/ucli/settings/gnome}"

if ! command -v dconf >/dev/null 2>&1; then
  echo "missing required command: dconf (package: dconf)" >&2
  exit 1
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "missing required command: gnome-extensions (package: gnome-shell-extensions)" >&2
  exit 1
fi

if [[ ! -d "$input_dir" ]]; then
  echo "No GNOME settings backup found: $input_dir" >&2
  echo "Run 'ucli backup-gnome-settings' first to create one." >&2
  exit 1
fi

echo "Restoring GNOME settings from: $input_dir"

# --- dconf settings ---
load_if_present() {
  local path="$1"
  local file="$2"
  if [[ -s "$input_dir/$file" ]]; then
    echo "Loading $file into $path"
    dconf load "$path" < "$input_dir/$file"
  else
    echo "Skipping missing/empty $file"
  fi
}

load_if_present /org/gnome/desktop/ desktop.dconf
load_if_present /org/gnome/shell/ shell.dconf
load_if_present /org/gnome/shell/extensions/ extensions.dconf

# --- Re-enable extensions ---
if [[ -s "$input_dir/enabled-extensions.txt" ]]; then
  echo "Re-enabling GNOME extensions..."
  while IFS= read -r uuid; do
    [[ -z "$uuid" ]] && continue
    gnome-extensions enable "$uuid" 2>/dev/null || \
      echo "  warning: could not enable $uuid (may not be installed yet)" >&2
  done < "$input_dir/enabled-extensions.txt"
else
  echo "No enabled-extensions.txt found; skipping extension re-enable."
fi

echo ""
echo "Restore complete."
echo "  Some settings may require a GNOME Shell restart (Alt+F2, r, Enter) or re-login."
