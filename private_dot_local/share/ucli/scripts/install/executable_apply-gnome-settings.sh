#!/usr/bin/env bash
set -euo pipefail

settings_dir="${1:-$HOME/.local/share/ucli/settings/gnome}"

if [[ ! -d "$settings_dir" ]]; then
  echo "No GNOME settings profile found: $settings_dir"
  exit 0
fi

if ! command -v dconf >/dev/null 2>&1; then
  echo "missing required command: dconf" >&2
  exit 1
fi

load_if_present() {
  local path="$1"
  local file="$2"
  if [[ -s "$settings_dir/$file" ]]; then
    echo "Loading $file into $path"
    dconf load "$path" < "$settings_dir/$file"
  else
    echo "Skipping missing/empty $file"
  fi
}

load_if_present /org/gnome/desktop/ desktop.dconf
load_if_present /org/gnome/shell/ shell.dconf
load_if_present /org/gnome/shell/extensions/ extensions.dconf
