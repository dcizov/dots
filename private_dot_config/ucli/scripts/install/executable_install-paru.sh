#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-paru.sh [--yes]

Install paru idempotently.
- On CachyOS: installs paru with pacman if available.
- On Arch: clones https://aur.archlinux.org/paru.git and builds with makepkg -si.
USAGE
}

yes_flag=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

if command -v paru >/dev/null 2>&1; then
  echo "paru already installed: $(command -v paru)"
  exit 0
fi

if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found; cannot install paru" >&2
  exit 1
fi

. /etc/os-release
id_like=" ${ID:-} ${ID_LIKE:-} "

sudo pacman -S --needed git base-devel

if [[ " $id_like " == *" cachyos "* ]] || pacman -Si paru >/dev/null 2>&1; then
  sudo pacman -S --needed paru
  exit 0
fi

workdir="${TMPDIR:-/tmp}/paru-build-${USER}"
rm -rf "$workdir"
git clone https://aur.archlinux.org/paru.git "$workdir"
cd "$workdir"

if (( yes_flag )); then
  makepkg -si --noconfirm
else
  makepkg -si
fi
