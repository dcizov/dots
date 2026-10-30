#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-better-tray-icons.sh [--update] [--enable]

Clone/build/install Better Tray Icons from upstream GitHub using its Makefile.
This follows the upstream installation wiki.

Source: https://github.com/nexaknight/BetterTrayIcons
UUID:   BetterTrayIcons@nexaknight.com
USAGE
}

update=0
enable=1
while (($#)); do
  case "$1" in
    --update) update=1; shift ;;
    --enable) enable=1; shift ;;
    --no-enable) enable=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

repo_url="https://github.com/nexaknight/BetterTrayIcons.git"
workdir="${XDG_CACHE_HOME:-$HOME/.cache}/ucli/BetterTrayIcons"
uuid="BetterTrayIcons@nexaknight.com"

for cmd in git make gnome-extensions; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
done

# Upstream build requirements include git, glib-compile-schemas (glib2), gettext/msgfmt,
# node/npm, and make. Install missing Arch packages if pacman is available.
if command -v pacman >/dev/null 2>&1; then
  missing="$(pacman -T git glib2 gettext nodejs npm make 2>/dev/null || true)"
  if [[ -n "$missing" ]]; then
    sudo pacman -S --needed $missing
  fi
fi

mkdir -p "$(dirname "$workdir")"

if [[ -d "$workdir/.git" ]]; then
  if (( update )); then
    git -C "$workdir" pull --ff-only
  else
    echo "Repository already exists: $workdir"
    echo "Use --update to pull latest changes before install."
  fi
else
  git clone "$repo_url" "$workdir"
fi

make -C "$workdir" install

if (( enable )); then
  gnome-extensions enable "$uuid" || {
    echo "Installed $uuid, but enabling failed. Log out/in, then enable it with:" >&2
    echo "  gnome-extensions enable '$uuid'" >&2
  }
fi

echo "Better Tray Icons installed from source."
echo "A GNOME logout/login is recommended after install/update."
