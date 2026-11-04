#!/usr/bin/env bash
# Config drift: what on this machine no longer matches the package that shipped
# it. The Arch answer to Bluefin's `ujust check-local-overrides` (which diffs
# /usr/etc against /etc); here the same question is "which packaged files did I
# edit, and which new defaults are waiting to be merged".
#
#   1. .pacnew / .pacsave — a package shipped a new config, nobody merged it
#   2. pacman -Qkk        — files whose checksum/size/type differ from the package
#
# Read-only: prints, changes nothing, exits 0 even when it finds drift (drift is
# normal, it just should not be invisible).
#
# Usage: config-audit.sh [--max N]
set -uo pipefail

max=10
while (($#)); do
  case "$1" in
    --max) max="${2:?--max needs a number}"; shift 2 ;;
    --max=*) max="${1#*=}"; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

echo "== config drift =="

# --- 1. new defaults that are waiting ---------------------------------------
echo
echo "-- unmerged package configs (.pacnew / .pacsave)"
conflicts=""
if have pacdiff; then
  conflicts="$(pacdiff -o 2>/dev/null || true)"
else
  conflicts="$(find /etc -name '*.pacnew' -o -name '*.pacsave' 2>/dev/null | sort || true)"
fi

if [[ -n "$conflicts" ]]; then
  count="$(printf '%s\n' "$conflicts" | wc -l | tr -d ' ')"
  echo "   $count file(s) need attention:"
  printf '%s\n' "$conflicts" | head -n "$max" | sed 's/^/     /'
  if (( count > max )); then echo "     … and $((count - max)) more"; fi
  echo
  echo "   merge them with: sudo pacdiff   (needs pacman-contrib, which base installs)"
else
  echo "   none — every package config has been merged"
fi

# --- 2. locally modified packaged files -------------------------------------
echo
echo "-- packaged files that differ from their package (pacman -Qkk)"
if ! have pacman; then
  echo "   pacman not found; skipping"
  exit 0
fi

# -Qkk as the user is enough for /etc and $HOME paths; a handful of warnings for
# root-only files are expected, so the summary is the interesting part.
kk="$(pacman -Qkk 2>/dev/null || true)"
mismatched="$(printf '%s\n' "$kk" | grep -E 'warning: .* (checksum|size|type|target) mismatch' || true)"
perm_only="$(printf '%s\n' "$kk" | grep -c 'Permissions mismatch' || true)"

if [[ -z "$mismatched" ]]; then
  echo "   none — no packaged file has been edited (only permission/mtime noise)"
else
  pkgs="$(printf '%s\n' "$mismatched" | sed -E 's/, file .*//' | sed -E 's/.*warning: //' | sort -u)"
  n_pkgs="$(printf '%s\n' "$pkgs" | wc -l | tr -d ' ')"
  n_files="$(printf '%s\n' "$mismatched" | wc -l | tr -d ' ')"
  echo "   $n_files file(s) across $n_pkgs package(s):"
  printf '%s\n' "$pkgs" | head -n "$max" | sed 's/^/     /'
  if (( n_pkgs > max )); then echo "     … and $((n_pkgs - max)) more package(s)"; fi
  echo
  echo "   full list: sudo pacman -Qkk | grep mismatch"
  echo "   these are files you (or a hook) changed; a package upgrade may overwrite them"
fi
if [[ -n "${perm_only:-}" && "$perm_only" != 0 ]]; then
  echo "   ($perm_only permission mismatch(es) ignored — normal when not running as root)"
fi

echo
echo "== done. nothing was changed. =="
