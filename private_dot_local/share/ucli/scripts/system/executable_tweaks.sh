#!/usr/bin/env bash
# Turn a registered service on or off: `ucli tweak list|enable|disable <name>`.
#
# The registry is TWEAKS in packages.bash (name|unit|package|kind|description), so
# the switches live next to the package lists they belong to and a machine can
# override them in packages.local.bash. This is the CachyOS-Hello "tweaks" page
# without its performance catalogue: what is here is Bluetooth, printing, TRIM,
# firmware refresh, Syncthing, libvirt, ufw and power profiles.
#
#   ucli tweak list                  every entry: package installed? unit running?
#   ucli tweak enable <name>         install the package (repos only) and start it
#   ucli tweak disable <name>        stop and disable it, KEEP the package
#   ucli tweak status <name>
#
# Differences from CachyOS Hello on purpose:
#   * disabling never uninstalls the package — removal belongs to
#     `ucli debloat-desktop`, where it is snapshot-guarded;
#   * there is no state file. `systemctl is-enabled` is the state.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

usage() {
  cat <<'USAGE'
usage: tweaks.sh list
       tweaks.sh enable <name> [--dry-run] [--no-install]
       tweaks.sh disable <name> [--dry-run]
       tweaks.sh status <name>

Toggles the services in TWEAKS (packages.bash). enable installs the package when
it is missing from the repos and starts the unit; disable stops and disables it
and keeps the package.
USAGE
}

action=""
name=""
dry_run=0
no_install=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --dry-run|-n) dry_run=1 ;;
    --no-install) no_install=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) if [[ -z "$action" ]]; then action="$arg"; elif [[ -z "$name" ]]; then name="$arg"; else
         echo "unexpected argument: $arg" >&2; exit 2
       fi ;;
  esac
done

packages_bash="$real_home/.config/ucli/packages.bash"
if [[ ! -r "$packages_bash" ]]; then
  echo "no package registry at $packages_bash (run the bootstrap first)" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$packages_bash"

if ! declare -p TWEAKS >/dev/null 2>&1 || (( ${#TWEAKS[@]} == 0 )); then
  echo "TWEAKS is empty in $packages_bash" >&2
  exit 1
fi

# Expand a unit template for this user: syncthing@.service → syncthing@alice.service
unit_for() {
  local unit="$1" kind="$2"
  if [[ "$kind" == template && "$unit" == *"@."* ]]; then
    printf '%s@%s.%s\n' "${unit%%@.*}" "$real_user" "${unit##*@.}"
  else
    printf '%s\n' "$unit"
  fi
}

entry_for() {
  local want="$1" entry n
  for entry in "${TWEAKS[@]}"; do
    n="${entry%%|*}"
    [[ "$n" == "$want" ]] && { printf '%s\n' "$entry"; return 0; }
  done
  return 1
}

pkg_installed() { pacman -Q "$1" >/dev/null 2>&1; }
unit_enabled()  { systemctl is-enabled --quiet "$1" >/dev/null 2>&1; }
unit_active()   { systemctl is-active --quiet "$1" >/dev/null 2>&1; }

list_tweaks() {
  ui_rule "tweaks (TWEAKS in packages.bash)"
  local entry n unit pkg kind desc state
  for entry in "${TWEAKS[@]}"; do
    IFS='|' read -r n unit pkg kind desc <<<"$entry"
    unit="$(unit_for "$unit" "$kind")"
    state="off"
    unit_enabled "$unit" && state="enabled"
    unit_active "$unit" && state="running"
    if pkg_installed "$pkg"; then
      pkg="${pkg} ✓"
    else
      pkg="${pkg} (not installed)"
    fi
    printf '  %-13s %-34s %-9s %-26s %s\n' "$n" "$unit" "$state" "$pkg" "$desc"
  done
  echo
  printf '  on:  sudo ucli tweak enable <name>      off: sudo ucli tweak disable <name>\n'
}

status_one() {
  local entry n unit pkg kind desc
  entry="$(entry_for "$1")" || { echo "no such tweak: $1 (try 'ucli tweak list')" >&2; return 2; }
  IFS='|' read -r n unit pkg kind desc <<<"$entry"
  unit="$(unit_for "$unit" "$kind")"
  printf '%s\n' "$desc"
  printf '  unit:    %s\n' "$unit"
  printf '  package: %s (%s)\n' "$pkg" "$(pkg_installed "$pkg" && echo installed || echo missing)"
  printf '  enabled: %s\n' "$(unit_enabled "$unit" && echo yes || echo no)"
  printf '  active:  %s\n' "$(unit_active "$unit" && echo yes || echo no)"
}

enable_tweak() {
  local entry n unit pkg kind desc
  entry="$(entry_for "$1")" || { echo "no such tweak: $1 (try 'ucli tweak list')" >&2; return 2; }
  IFS='|' read -r n unit pkg kind desc <<<"$entry"
  unit="$(unit_for "$unit" "$kind")"

  if unit_enabled "$unit" && unit_active "$unit"; then
    echo "$n is already enabled and running ($unit)"
    return 0
  fi

  if ! pkg_installed "$pkg"; then
    if (( no_install )); then
      echo "package $pkg is not installed and --no-install was given" >&2
      return 1
    fi
    if ! pacman -Si "$pkg" >/dev/null 2>&1; then
      echo "package $pkg is not in the configured repositories" >&2
      echo "  install it first (ucli sync / ucli virt install theirs), then re-run" >&2
      return 1
    fi
    if (( dry_run )); then
      printf '+ sudo pacman -S --needed --noconfirm %s\n' "$pkg"
    else
      ui_rule "installing $pkg"
      sudo pacman -S --needed --noconfirm "$pkg"
    fi
  fi

  if (( dry_run )); then
    printf '+ sudo systemctl enable --now %s\n' "$unit"
    return 0
  fi
  ui_rule "enabling $n"
  sudo systemctl enable --now "$unit"
  ui_ok "$n enabled ($unit)"
}

disable_tweak() {
  local entry n unit pkg kind desc
  entry="$(entry_for "$1")" || { echo "no such tweak: $1 (try 'ucli tweak list')" >&2; return 2; }
  IFS='|' read -r n unit pkg kind desc <<<"$entry"
  unit="$(unit_for "$unit" "$kind")"

  if ! unit_enabled "$unit" && ! unit_active "$unit"; then
    echo "$n is already off ($unit)"
    return 0
  fi
  if (( dry_run )); then
    printf '+ sudo systemctl disable --now %s\n' "$unit"
    return 0
  fi
  ui_rule "disabling $n"
  sudo systemctl disable --now "$unit"
  ui_ok "$n disabled ($unit)"
  printf "  the %s package stays installed; removing it is what ucli debloat-desktop is for.\n" "$pkg"
}

case "$action" in
  list|"") list_tweaks ;;
  status)
    [[ -n "$name" ]] || { echo "usage: tweaks.sh status <name>" >&2; exit 2; }
    status_one "$name" ;;
  enable)
    [[ -n "$name" ]] || { echo "usage: tweaks.sh enable <name>" >&2; exit 2; }
    enable_tweak "$name" ;;
  disable)
    [[ -n "$name" ]] || { echo "usage: tweaks.sh disable <name>" >&2; exit 2; }
    disable_tweak "$name" ;;
  *) usage; exit 2 ;;
esac
