#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-$HOME/system-inventory/clean-$(date +%F-%H%M%S)}"
mkdir -p "$OUT"/{packages,flatpak,gnome,appimages,dconf}

# Pacman/AUR inventory.
pacman -Qqen > "$OUT/packages/pacman-explicit-native.txt"
pacman -Qqem > "$OUT/packages/aur-explicit.txt" || true      # exit 1 when there are no foreign packages
pacman -Qqe  > "$OUT/packages/explicit-all.txt"
pacman -Qq   > "$OUT/packages/all-installed.txt"
pacman -Qen  > "$OUT/packages/pacman-explicit-native-with-versions.txt"
pacman -Qem  > "$OUT/packages/aur-explicit-with-versions.txt" || true      # exit 1 when there are no foreign packages
pacman -Qe   > "$OUT/packages/explicit-all-with-versions.txt"

# Flatpak inventory.
if command -v flatpak >/dev/null 2>&1; then
  flatpak list --app --columns=application,name,branch,origin,installation > "$OUT/flatpak/apps.tsv" || true
  flatpak list --app --columns=application > "$OUT/flatpak/app-ids.txt" || true
  flatpak list --user --app --columns=application > "$OUT/flatpak/user-app-ids.txt" 2>/dev/null || true
  flatpak list --system --app --columns=application > "$OUT/flatpak/system-app-ids.txt" 2>/dev/null || true
  flatpak list --runtime --columns=application,branch,origin,installation > "$OUT/flatpak/runtimes.tsv" || true
  flatpak override --show --user > "$OUT/flatpak/user-overrides.txt" 2>/dev/null || true
  flatpak override --show --system > "$OUT/flatpak/system-overrides.txt" 2>/dev/null || true
fi

# GNOME extensions and settings.
if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions list > "$OUT/gnome/extensions-all.txt" || true
  gnome-extensions list --enabled > "$OUT/gnome/extensions-enabled.txt" || true
  gnome-extensions list --disabled > "$OUT/gnome/extensions-disabled.txt" || true
  while read -r ext; do
    [[ -n "$ext" ]] || continue
    echo "## $ext"
    gnome-extensions info "$ext" || true
    echo
  done < <(gnome-extensions list || true) > "$OUT/gnome/extensions-info.txt"
fi

find "$HOME/.local/share/gnome-shell/extensions" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null > "$OUT/gnome/extensions-user-installed.txt" || true
find /usr/share/gnome-shell/extensions -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null > "$OUT/gnome/extensions-system-installed.txt" || true
pacman -Qqe | grep -E '^gnome-shell-extension|^gnome-browser-connector' > "$OUT/gnome/gnome-extension-packages-native.txt" || true
pacman -Qqem | grep -E '^gnome-shell-extension' > "$OUT/gnome/gnome-extension-packages-aur.txt" || true

if command -v dconf >/dev/null 2>&1; then
  dconf dump /org/gnome/ > "$OUT/dconf/org-gnome.ini" || true
  dconf dump /org/gnome/shell/ > "$OUT/dconf/org-gnome-shell.ini" || true
  dconf dump /org/gnome/shell/extensions/ > "$OUT/dconf/org-gnome-shell-extensions.ini" || true
  dconf dump /org/gnome/desktop/ > "$OUT/dconf/org-gnome-desktop.ini" || true
  dconf dump /org/gnome/mutter/ > "$OUT/dconf/org-gnome-mutter.ini" || true
  dconf dump /org/gnome/settings-daemon/ > "$OUT/dconf/org-gnome-settings-daemon.ini" || true
fi

# AppImage inventory.
find "$HOME" -type f \( -iname '*.AppImage' -o -iname '*.appimage' \) -printf '%p\n' 2>/dev/null > "$OUT/appimages/appimages.txt" || true
find "$HOME/.local/share/applications" -type f -name '*.desktop' -print0 2>/dev/null | xargs -0 grep -Il 'AppImage' 2>/dev/null > "$OUT/appimages/appimage-desktop-files.txt" || true
while read -r file; do
  [[ -f "$file" ]] || continue
  sha256sum "$file"
done < "$OUT/appimages/appimages.txt" > "$OUT/appimages/appimages.sha256.txt"

echo "$OUT"
if command -v tree >/dev/null 2>&1; then
  tree "$OUT"
fi
