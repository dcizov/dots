#!/usr/bin/env bash
# Config drift: what on this machine no longer matches the package that shipped
# it. The Arch answer to Bluefin's `ujust check-local-overrides` (which diffs
# /usr/etc against /etc); here the same question is "which packaged files did I
# edit, and which new defaults are waiting to be merged".
#
#   1. .pacnew / .pacsave — a package shipped a new config, nobody merged it
#   2. pacman -Qkk        — files whose checksum/size/type differ from the package,
#                           split into ordinary files (an upgrade overwrites them)
#                           and backup= configs (an upgrade leaves a .pacnew)
#
# Read-only: prints, changes nothing, exits 0 even when it finds drift (drift is
# normal, it just should not be invisible).
#
# Usage: config-audit.sh [--max N]
set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$script_dir/../lib/common.sh"

max=10
while (($#)); do
  case "$1" in
    --max) max="${2:-}"; shift $(( $# >= 2 ? 2 : 1 )) ;;
    --max=*) max="${1#*=}"; shift ;;
    -h|--help) ucli_script_help; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$max" =~ ^[1-9][0-9]*$ ]] || { echo "--max needs a positive number, got: ${max:-nothing}" >&2; exit 2; }

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

# pacman -Qkk reports one line per differing property, on stderr (stdout has
# only the per-package totals):
#   warning: <pkg>: <path> (<what> mismatch)       an ordinary packaged file
#   backup file: <pkg>: <path> (<what> mismatch)   a config listed in backup=()
# Content changes are checksum, Size, Type and Symlink path; mtime, permission
# and owner lines are noise. Files are counted by "<pkg>: <path>", because one
# edited file shows up once per property. -Qkk as the user covers /etc and
# $HOME; root-only files only produce "failed to calculate" lines, ignored.
kk="$(pacman -Qkk 2>&1 || true)"
content='\(((SHA256|MD5) checksum|Size|Type|Symlink path) mismatch\)$'

# changed_files <prefix> — "<pkg>: <path>" for every content mismatch.
changed_files() {
  printf '%s\n' "$kk" | grep -E "^$1: [^:]+: .+ $content" |
    sed -E "s/^$1: (.+) \\([^()]*\\)\$/\\1/" | sort -u || true
}

# summarise <files> <advice> — "N file(s) across M package(s)" plus the
# first --max package names.
summarise() {
  local files="$1" pkgs n_pkgs n_files
  pkgs="$(printf '%s\n' "$files" | sed -E 's/^([^:]+): .*/\1/' | sort -u)"
  n_pkgs="$(printf '%s\n' "$pkgs" | wc -l | tr -d ' ')"
  n_files="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
  echo "   $n_files file(s) across $n_pkgs package(s):"
  printf '%s\n' "$pkgs" | head -n "$max" | sed 's/^/     /'
  if (( n_pkgs > max )); then echo "     … and $((n_pkgs - max)) more package(s)"; fi
  echo "   $2"
}

packaged="$(changed_files warning)"
configs="$(changed_files 'backup file')"
perm_only="$(printf '%s\n' "$kk" | grep -c '(Permissions mismatch)$' || true)"

if [[ -z "$packaged" ]]; then
  echo "   none — no packaged file has been edited (only permission/mtime noise)"
else
  summarise "$packaged" "you (or a hook) changed these; the next upgrade of the package overwrites them"
fi
echo
echo "-- edited configuration files (backup=, kept across upgrades)"
if [[ -z "$configs" ]]; then
  echo "   none — every packaged config is as shipped"
else
  summarise "$configs" "normal for /etc/fstab, passwd and friends; new defaults arrive as .pacnew instead"
fi
echo
echo "   full list: pacman -Qkk 2>&1 | grep mismatch"
if [[ -n "${perm_only:-}" && "$perm_only" != 0 ]]; then
  echo "   ($perm_only permission mismatch(es) ignored — normal when not running as root)"
fi

echo
echo "== done. nothing was changed. =="
