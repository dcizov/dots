#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: gnome-settings.sh COMMAND

Commands:
  backup [DIR]                 Dump GNOME dconf settings to DIR
  restore-shell DIR            Restore /org/gnome/shell/ from DIR/org-gnome-shell.ini
  restore-extensions DIR       Restore /org/gnome/shell/extensions/ from DIR/org-gnome-shell-extensions.ini
  restore-desktop DIR          Restore /org/gnome/desktop/ from DIR/org-gnome-desktop.ini
USAGE
}

cmd="${1:-}"
shift || true
[[ -n "$cmd" ]] || { usage; exit 2; }

case "$cmd" in
  backup)
    out="${1:-$HOME/system-inventory/gnome-dconf-$(date +%F-%H%M%S)}"
    mkdir -p "$out"
    dconf dump /org/gnome/ > "$out/org-gnome.ini"
    dconf dump /org/gnome/shell/ > "$out/org-gnome-shell.ini"
    dconf dump /org/gnome/shell/extensions/ > "$out/org-gnome-shell-extensions.ini"
    dconf dump /org/gnome/desktop/ > "$out/org-gnome-desktop.ini"
    dconf dump /org/gnome/mutter/ > "$out/org-gnome-mutter.ini"
    dconf dump /org/gnome/settings-daemon/ > "$out/org-gnome-settings-daemon.ini"
    echo "$out"
    ;;
  restore-shell)
    dir="${1:?DIR required}"
    dconf load /org/gnome/shell/ < "$dir/org-gnome-shell.ini"
    ;;
  restore-extensions)
    dir="${1:?DIR required}"
    dconf load /org/gnome/shell/extensions/ < "$dir/org-gnome-shell-extensions.ini"
    ;;
  restore-desktop)
    dir="${1:?DIR required}"
    dconf load /org/gnome/desktop/ < "$dir/org-gnome-desktop.ini"
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
