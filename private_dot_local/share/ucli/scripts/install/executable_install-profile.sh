#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# Args: an optional desktop name, plus the flags shared by the machine-setup steps.
#   --no-snapshot   no restore point before or after (also UCLI_NO_SNAPSHOT=1)
#   --yes           assume yes for the preflight question
desktop=""
take_snapshot=1
for arg in "$@"; do
  case "$arg" in
    --no-snapshot) take_snapshot=0 ;;
    --yes|-y) UCLI_YES=1 ;;
    --help|-h)
      cat <<'EOF'
usage: install-profile.sh [--no-snapshot] [--yes] [gnome|kde|hyprland]

The machine step: base packages, then the desktop step (DE, firefox + terminal,
shell tier, dotfiles, GNOME extensions, snapshot).

  --no-snapshot   skip every Snapper snapshot of this run (UCLI_NO_SNAPSHOT=1 too)
  --yes           do not ask when there is no snapper config
EOF
      exit 0
      ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) desktop="$arg" ;;
  esac
done
UCLI_NO_SNAPSHOT="${UCLI_NO_SNAPSHOT:-0}"
if (( ! take_snapshot )); then UCLI_NO_SNAPSHOT=1; fi
export UCLI_NO_SNAPSHOT

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"


# Preflight: the desktop step is the destructive one (packages, chsh, a snapshot
# at the end), so on a machine with no snapper config warn and — on a TTY — ask.
# Same rule as `ucli update`: a pipe/non-TTY proceeds, UCLI_YES=1 proceeds.
if [[ ! -f /etc/snapper/configs/root ]] && [[ "$UCLI_NO_SNAPSHOT" != "1" ]]; then
  echo "warning: no Snapper config found — the desktop step will not be able to"
  echo "         create a restore point first. 'ucli setup-snapshots' sets it up."
  if [[ -t 0 && "${UCLI_YES:-0}" != "1" ]]; then
    read -rp "Continue without snapshots? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "aborted. run 'ucli setup-snapshots' first."
      exit 1
    fi
  fi
fi

# Restore point before hundreds of packages arrive. The same script as every other
# snapshot in the repo, so --no-snapshot / UCLI_NO_SNAPSHOT=1 covers this one too;
# it no-ops when snapper is not configured (feasible on CachyOS, not on archinstall).
pre_args=()
(( take_snapshot )) || pre_args+=(--no-snapshot)
sudo "$script_dir/../system/snapshot-fresh-install.sh" ${pre_args[@]+"${pre_args[@]}"} \
  "before setup-system" || echo "warning: could not take a restore point; continuing" >&2

# base = the machine itself: bootstrap, cpu/gpu, system tools, fonts, ucli runtime.
"$script_dir/install-packages.sh" base
"$script_dir/install-flatpaks.sh" base

# The desktop is one owner: setup-desktop.sh installs the DE with the
# replacement matrix, adds ghostty + firefox, installs/enables the GNOME
# extensions and takes a snapshot. Pass the desktop as $1 ("gnome", "kde",
# "hyprland") or leave it empty to let it auto-detect/prompt.
desktop_args=()
[[ -n "$desktop" ]] && desktop_args+=("$desktop")
(( take_snapshot )) || desktop_args+=(--no-snapshot)
if [[ -x "$script_dir/setup-desktop.sh" ]]; then
  sudo "$script_dir/setup-desktop.sh" ${desktop_args[@]+"${desktop_args[@]}"}
else
  echo "warning: setup-desktop.sh missing; install the desktop yourself" >&2
fi