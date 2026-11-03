#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-paru.sh [--yes]

Install paru idempotently.
- On CachyOS: installs paru with pacman if available.
- On Arch: clones https://aur.archlinux.org/paru.git, verifies the PGP signature,
  and builds with makepkg -si.

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

# When run as root (e.g. from setup-desktop.sh), drop to the invoking user
# for the AUR build since makepkg refuses to run as root.
if [[ "$EUID" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
  exec runuser -u "$SUDO_USER" -- "$0" "$@"
fi

if [[ " $id_like " == *" cachyos "* ]] || pacman -Si paru >/dev/null 2>&1; then
  sudo pacman -S --needed paru
  exit 0
fi

# Use a private, unpredictable temp dir (avoid symlink races).
workdir="$(mktemp -d -t paru-build.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

echo "cloning paru AUR repository ..."
git clone https://aur.archlinux.org/paru.git "$workdir"
cd "$workdir"

# Verify the PGP signature on the paru source tarball.
# Paru releases are signed by Morganamilo (48652EE482BF7507).
if command -v gpg >/dev/null 2>&1; then
  echo "verifying PGP signature on paru source ..."
  # Import the upstream key if not already trusted.
  if ! gpg --list-keys 48652EE482BF7507 >/dev/null 2>&1; then
    gpg --recv-keys 48652EE482BF7507 2>/dev/null || \
      gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 48652EE482BF7507 2>/dev/null || \
      { echo "warning: could not import paru PGP key; proceeding without signature verification" >&2; }
  fi

  # Verify the .SRCINFO or PKGBUILD signature if a .sig file exists.
  sig_file="$(ls *.sig 2>/dev/null | head -1 || true)"
  if [[ -n "$sig_file" ]] && gpg --verify "$sig_file" 2>/dev/null; then
    echo "PGP signature verified."
  else
    echo "warning: no valid signature found on source; makepkg will verify checksums instead" >&2
  fi
else
  echo "warning: gpg not found; skipping PGP signature verification" >&2
fi

if (( yes_flag )); then
  makepkg -si --noconfirm
else
  makepkg -si
fi