#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-paru.sh [--yes]

Install paru idempotently.
- On CachyOS: installs paru with pacman if available.
- On Arch: imports the paru PGP key, clones https://aur.archlinux.org/paru.git
  and builds with makepkg -si (which checks the signed source against it).

Paru PGP key: 48652EE482BF7507 (Morganamilo <mail@morganamilo.com>)
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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/aur.sh
. "$script_dir/../lib/aur.sh"
key="48652EE482BF7507"   # Morganamilo, paru's release signing key

if command -v paru >/dev/null 2>&1; then
  echo "paru already installed: $(command -v paru)" >&2
  exit 0
fi
if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found; cannot install paru" >&2
  exit 1
fi

# A repository package beats an AUR build — signed, updated, no makepkg, and it
# works on a machine with no helper at all. CachyOS carries both shelly and paru
# in its own repositories; Arch does not.
if pacman -Si paru >/dev/null 2>&1; then
  echo "paru is in the configured repositories; installing with pacman" >&2
  sudo pacman -S --needed --noconfirm paru >&2
  exit 0
fi

if (( yes_flag )); then
  sudo pacman -S --needed --noconfirm git base-devel >&2
else
  sudo pacman -S --needed git base-devel >&2
fi

# makepkg refuses to run as root: from setup-desktop (sudo) build as the user.
if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
  exec runuser -u "$SUDO_USER" -- "${BASH_SOURCE[0]}" "$@"
fi

aur_build paru "$yes_flag" "$key"
