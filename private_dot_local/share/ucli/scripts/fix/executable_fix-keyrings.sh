#!/usr/bin/env bash
# Repair pacman's keyring: the "invalid or corrupted package (PGP signature)" and
# "key could not be looked up remotely" class of failures.
#
#   sudo ucli fix keyrings            refresh the keys from the keyservers
#   sudo ucli fix keyrings --reset    re-initialise the keyring, then populate it
#   sudo ucli fix keyrings --dry-run  say what would run
#
# The gentle path first (`--refresh-keys`), the destructive-but-effective path
# only when asked for or when the refresh fails: `pacman-key --init` regenerates
# the local master key and `--populate` re-imports the packager keys from
# /usr/share/pacman/keyrings (archlinux, plus cachyos on CachyOS). Neither touches
# installed packages.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

reset=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --reset) reset=1 ;;
    --dry-run|-n) dry_run=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# UCLI_TEST_ROOT is the test seam (setup-boot.sh has the same idea): with it
# set, the root check is skipped so the logic can be exercised on a temp tree.
if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Run as root: sudo ucli fix keyrings" >&2
  exit 1
fi

run() {
  printf '+ %s\n' "$*"
  if (( dry_run )); then return 0; fi
  "$@"
}

keyrings=()
for candidate in archlinux cachyos; do
  compgen -G "/usr/share/pacman/keyrings/${candidate}.gpg" >/dev/null 2>&1 && keyrings+=("$candidate")
done
(( ${#keyrings[@]} )) || keyrings=(archlinux)

ui_rule "pacman keyring"
printf '  keyrings available: %s\n' "${keyrings[*]}"

if (( reset )); then
  ui_rule "re-initialising the keyring"
  run pacman-key --init
  for k in "${keyrings[@]}"; do
    run pacman-key --populate "$k"
  done
  ui_rule "refreshing keys"
  run pacman-key --refresh-keys
else
  ui_rule "refreshing keys (this can take a minute)"
  if (( dry_run )); then
    run pacman-key --refresh-keys
  elif ! pacman-key --refresh-keys; then
    echo "warning: refresh failed (keyserver or network); trying the local keyrings" >&2
    pacman-key --init
    for k in "${keyrings[@]}"; do
      pacman-key --populate "$k"
    done
  fi
fi

if (( ! dry_run )); then
  keys="$(pacman-key --list-keys 2>/dev/null | grep -c '^pub' || true)"
  ui_rule "keyring check"
  printf '  public keys: %s\n' "${keys:-0}"
  ui_rule "next"
  printf '  retry the install/upgrade that failed; if one package is still refused,\n'
  printf '  clear its cached download: sudo rm -f /var/cache/pacman/pkg/<pkg>-*.pkg.tar.*\n'
fi
