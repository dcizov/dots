#!/usr/bin/env bash
# Create an ad-hoc "pet" container from a stock image — the Arch equivalent of
# the preconfigured Ubuntu / Fedora / Wolfi boxes Bluefin ships for distrobox.
#
# The `dev` box in this repo stays the one that is provisioned (dev.ini,
# provision-dev.sh, node + php). These are throwaway: pick a distro, get a shell
# with your $HOME inside it, delete it whenever.
#
# Usage: devbox-create.sh [ubuntu|fedora|wolfi|debian|arch|alpine] [NAME]
#        devbox-create.sh --list
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
  exit 0
fi

image_for() {
  case "$1" in
    ubuntu) printf 'docker.io/library/ubuntu:24.04' ;;
    fedora) printf 'docker.io/library/fedora:latest' ;;
    wolfi)  printf 'cgr.dev/chainguard/wolfi-base:latest' ;;
    debian) printf 'docker.io/library/debian:stable' ;;
    arch)   printf 'docker.io/library/archlinux:latest' ;;
    alpine) printf 'docker.io/library/alpine:latest' ;;
    *) return 1 ;;
  esac
}

if [[ "${1:-}" == "--list" ]]; then
  echo "images:"
  for d in ubuntu fedora wolfi debian arch alpine; do
    printf '  %-7s %s\n' "$d" "$(image_for "$d")"
  done
  exit 0
fi

distro="${1:-}"
if [[ -z "$distro" ]]; then
  read -rp "Distro [ubuntu/fedora/wolfi/debian/arch/alpine]: " distro
fi
image="$(image_for "$distro" 2>/dev/null || true)"
if [[ -z "$image" ]]; then
  echo "unsupported distro: $distro (try --list)" >&2
  exit 2
fi

if ! command -v distrobox >/dev/null 2>&1; then
  echo "distrobox is not installed (run: ucli devmode)" >&2
  exit 1
fi

name="${2:-$distro}"
if distrobox list 2>/dev/null | awk -F'|' 'NR>1 {gsub(/ /,"",$2); print $2}' | grep -qx "$name"; then
  echo "container '$name' already exists; entering it"
else
  echo "creating '$name' from $image ..."
  distrobox create --name "$name" --image "$image" --yes
fi

echo
echo "Enter it with:  distrobox enter $name"
echo "Remove it with: distrobox rm -f $name"
