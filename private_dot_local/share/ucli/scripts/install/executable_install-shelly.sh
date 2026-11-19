#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-shelly.sh [--yes]

Install shelly idempotently (AUR helper for Arch/CachyOS).

- A no-op when shelly is already installed (it is the default helper on CachyOS).
- Repository first: if the configured repos carry shelly (CachyOS does), install
  it with pacman.
- Otherwise clone https://aur.archlinux.org/shelly.git and build it with
  makepkg -si (checksums verified by makepkg).

Shelly AUR package: https://aur.archlinux.org/packages/shelly
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
key=""   # the shelly PKGBUILD lists no validpgpkeys

if command -v shelly >/dev/null 2>&1; then
  echo "shelly already installed: $(command -v shelly)" >&2
  exit 0
fi
if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found; cannot install shelly" >&2
  exit 1
fi

# A repository package beats an AUR build — signed, updated, no makepkg, and it
# works on a machine with no helper at all. CachyOS carries both shelly and paru
# in its own repositories; Arch does not.
if pacman -Si shelly >/dev/null 2>&1; then
  echo "shelly is in the configured repositories; installing with pacman" >&2
  sudo pacman -S --needed --noconfirm shelly >&2
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

aur_build shelly "$yes_flag" "$key"
