#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-shelly.sh [--yes]

Install shelly idempotently (AUR helper for Arch/CachyOS).

- On CachyOS: shelly is preinstalled; this script is a no-op if shelly exists.
- On Arch/other: clones https://aur.archlinux.org/shelly.git, verifies the PGP
  signature if gpg is available, and builds with makepkg -si.

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

if command -v shelly >/dev/null 2>&1; then
  echo "shelly already installed: $(command -v shelly)"
  exit 0
fi

if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found; cannot install shelly" >&2
  exit 1
fi

sudo pacman -S --needed git base-devel

# When run as root (e.g. from setup-desktop.sh), drop to the invoking user
# for the AUR build since makepkg refuses to run as root.
if [[ "$EUID" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
  exec runuser -u "$SUDO_USER" -- "$0" "$@"
fi

# Use a private, unpredictable temp dir (avoid symlink races).
workdir="$(mktemp -d -t shelly-build.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

echo "cloning shelly AUR repository ..."
git clone https://aur.archlinux.org/shelly.git "$workdir"
cd "$workdir"

# Verify the PGP signature on the source tarball if gpg is available.
if command -v gpg >/dev/null 2>&1; then
  echo "verifying PGP signature on shelly source ..."
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
