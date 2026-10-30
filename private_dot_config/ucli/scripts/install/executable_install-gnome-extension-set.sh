#!/usr/bin/env bash
set -euo pipefail

usage() { echo 'usage: install-gnome-extension-set.sh system|overrides [--dry-run] [--force]'; }

mode=""
dry_run=0
force=0
for arg in "$@"; do
  case "$arg" in
    system|overrides) mode="$arg" ;;
    --dry-run|-n) dry_run=1 ;;
    --force) force=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$mode" ]] || { usage >&2; exit 2; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../../packages.bash"

case "$mode" in
  system)
    pk_array=GNOME_SYSTEM_EXTENSION_PKS
    uuid_array=GNOME_SYSTEM_EXTENSION_UUIDS
    ;;
  overrides)
    pk_array=GNOME_OVERRIDE_EXTENSION_PKS
    uuid_array=GNOME_OVERRIDE_EXTENSION_UUIDS
    ;;
esac

eval 'pks=("${'"$pk_array"'[@]:-}")'
eval 'uuids=("${'"$uuid_array"'[@]:-}")'

echo "GNOME extension set: $mode"
echo "extension pks: ${pks[*]:-(none)}"
echo "extension uuids: ${uuids[*]:-(none)}"
(( dry_run )) && exit 0

for cmd in curl python3 gnome-shell gnome-extensions; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd" >&2; exit 1; }
done

install_one="$script_dir/../gnome/install-gnome-extension.sh"
[[ -x "$install_one" ]] || { echo "missing install-gnome-extension.sh: $install_one" >&2; exit 1; }

for pk in "${pks[@]}"; do
  [[ -n "$pk" ]] || continue
  args=(--pk "$pk")
  (( force )) && args+=(--force)
  "$install_one" "${args[@]}" || echo "failed to install GNOME extension pk=$pk" >&2
done

for uuid in "${uuids[@]}"; do
  [[ -n "$uuid" ]] || continue
  gnome-extensions enable "$uuid" || echo "Could not enable $uuid now; log out/in and rerun this command." >&2
done

gnome-extensions list --enabled || true
