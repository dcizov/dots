#!/usr/bin/env bash
# Backup GNOME Shell settings and extensions for restore after reinstall.
#
# Usage: backup-gnome-settings.sh [output-dir]
#
# Default output: ~/.config/ucli/settings/gnome/  (chezmoi-managed)
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

output_dir="${1:-$HOME/.config/ucli/settings/gnome}"

if ! command -v dconf >/dev/null 2>&1; then
  echo "missing required command: dconf (package: dconf)" >&2
  exit 1
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "missing required command: gnome-extensions (package: gnome-shell-extensions)" >&2
  exit 1
fi

mkdir -p "$output_dir"

echo "Backing up GNOME settings to: $output_dir"

# --- dconf settings ---
dconf dump /org/gnome/desktop/ > "$output_dir/desktop.dconf" || true
dconf dump /org/gnome/shell/ > "$output_dir/shell.dconf" || true
dconf dump /org/gnome/shell/extensions/ > "$output_dir/extensions.dconf" || true

# --- Enabled extensions list ---
gnome-extensions list --enabled > "$output_dir/enabled-extensions.txt" || true

# --- All installed extensions (enabled + disabled) ---
gnome-extensions list > "$output_dir/installed-extensions.txt" || true

echo "Backup complete."
echo "  dconf:     $output_dir/desktop.dconf, shell.dconf, extensions.dconf"
echo "  enabled:   $output_dir/enabled-extensions.txt"
echo "  installed: $output_dir/installed-extensions.txt"
echo ""
echo "To restore: ucli restore-gnome-settings"
