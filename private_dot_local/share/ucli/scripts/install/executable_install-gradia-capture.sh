#!/usr/bin/env bash
set -euo pipefail

# Gradia Capture — the GNOME Shell half of the Gradia screenshot workflow: the
# built-in screenshot tool gains annotations, saving options and OCR through the
# Gradia app (Flathub be.alexandervanhee.gradia, or `gradia` in Extra).
#
# Nothing can install this for us:
#   * not on extensions.gnome.org — 2026-11-05 the EGO API has no uuid
#     gradia-integration@alexandervanhee.github.io, so `gext install` has nothing
#     to fetch;
#   * not packaged by Arch — `gradia` ships the app, not this extension, and there
#     is no separate package.
# Bluefin builds it into the image with the project's own build.sh. This does the
# same thing, per user, once, at setup time.
#
# Source: https://github.com/AlexanderVanhee/gradia-capture
#
# REF is a pinned commit, never a branch: the build runs `gnome-extensions pack`
# and installs the result, which is not something to do from whatever master
# happens to be that day. Bump it when upstream supports a newer shell — the
# metadata's shell-version list is the thing to check (49/50/51 at this commit).
# Enabling is not done here: install-gnome-extension-set.sh owns the single
# write to org.gnome.shell enabled-extensions.

repo_url="https://github.com/AlexanderVanhee/gradia-capture.git"
ref="0b7e47e1e5c1e68e234e4d2d24b307e1da1d18a9"   # 2026-10-16 "Add support for GNOME 51"
uuid="gradia-integration@alexandervanhee.github.io"

usage() {
  cat <<'USAGE'
usage: install-gradia-capture.sh [--force]

Builds Gradia Capture from its pinned upstream commit and installs it into
~/.local/share/gnome-shell/extensions.

  --force   rebuild even when the gate says this commit is already installed
USAGE
}

force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

# When run via sudo (from setup-desktop.sh), $HOME is root's home and a per-user
# extension installed by root lands in /root — the desktop session never sees it.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"
ext_dir="$real_home/.local/share/gnome-shell/extensions/$uuid"

as_user() {
  if [[ "$EUID" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
    runuser -u "$real_user" -- env HOME="$real_home" \
      PATH="$real_home/.local/bin:$PATH" "$@"
  else
    "$@"
  fi
}

# gnome-extensions lives in gnome-shell itself; `pack` shells out to zip.
if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "error: gnome-extensions not found (it ships inside gnome-shell)" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "error: git not found; install it first: sudo pacman -S --needed git" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip not found; 'gnome-extensions pack' needs it: sudo pacman -S --needed zip" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$real_home/.local/share/ucli/scripts/lib/version-script.sh"
gate_name="gnome-gradia-capture"
if ((!force)) && ! vs_check "$gate_name" user "$ref"; then
  if [[ -d "$ext_dir" ]]; then
    echo "Gradia Capture ${ref:0:12} already installed; skipping."
    exit 0
  fi
  # Same lesson as the extension sets: the gate is a fast path, not the truth.
  # An extension the shell disabled is not "removed", but a wiped ~/.local or a
  # `ucli debloat-desktop` is — so look at the directory before believing it.
  echo "Gradia Capture is recorded as installed but $ext_dir is missing; rebuilding."
fi

# Built in a throwaway clone, installed by UUID: build.sh produces
# <uuid>.shell-extension.zip next to the sources.
workdir="$(as_user mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Building Gradia Capture (${ref:0:12}) from $repo_url ..."
as_user git init -q "$workdir/src"
as_user git -C "$workdir/src" remote add origin "$repo_url"
if ! as_user git -C "$workdir/src" fetch -q --depth 1 origin "$ref"; then
  echo "error: could not fetch commit $ref (network, or upstream force-pushed)" >&2
  exit 1
fi
as_user git -C "$workdir/src" checkout -q FETCH_HEAD

if ! as_user bash -c 'cd "$1" && ./build.sh' _ "$workdir/src"; then
  echo "error: build.sh failed for Gradia Capture ($ref)" >&2
  exit 1
fi

zip_path="$workdir/src/$uuid.shell-extension.zip"
if [[ ! -f "$zip_path" ]]; then
  echo "error: build.sh did not produce $uuid.shell-extension.zip" >&2
  exit 1
fi

echo "Installing $uuid ..."
if ! as_user gnome-extensions install --force "$zip_path"; then
  echo "error: 'gnome-extensions install' failed for $uuid" >&2
  exit 1
fi
if [[ ! -d "$ext_dir" ]]; then
  echo "error: install reported success but $ext_dir does not exist" >&2
  exit 1
fi

vs_commit "$gate_name" user "$ref"
echo "ok: $uuid installed in ${ext_dir#"$real_home"/}"
echo "    log out and back in to load it (the extension set enables it)."
