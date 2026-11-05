#!/usr/bin/env bash
# `ucli fix` — the dispatcher behind the Fix group.
#
#   ucli fix                 the table
#   ucli fix keyrings|lock|orphans|cache|native [flags]
#
# Each action is its own script next to this one, so they can be run directly and
# tested on their own; this only routes and prints the table. Every action takes
# --dry-run, and the ones that remove or reinstall something also take --yes.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Repair something:

  keyrings   refresh pacman's keyring (--reset re-initialises + repopulates)
  lock       remove a stale /var/lib/pacman/db.lck (refuses while pacman runs)
  orphans    remove packages nothing requires any more
  cache      keep the 2 newest package versions, vacuum the journal (--keep N)
  native     reinstall every repository package in place (--list first)

Every action takes --dry-run. Run: sudo ucli fix <action>
USAGE
}

action="${1:-}"
case "$action" in
  ""|list|help) usage ;;
  keyrings|lock|orphans|cache|native)
    shift
    exec "$script_dir/fix-$action.sh" "$@"
    ;;
  *)
    printf 'unknown fix action: %s\n' "$action" >&2
    printf 'try: ucli fix\n' >&2
    exit 2
    ;;
esac
