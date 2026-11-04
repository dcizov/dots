#!/usr/bin/env bash
# Syncthing — "keep this folder in sync between two computers", the piece of
# Bluefin's Sync Folder that a dotfiles repo does not already cover (chezmoi
# handles dotfiles, not your files).
#
# What this does:
#   * installs `syncthing` from the repos (skipped when present)
#   * enables syncthing@<user>.service — the system template unit, which runs
#     the daemon as you, not root
#   * prints the Web GUI, this machine's device ID, and the pairing steps
#
# What it does not do: create the folder, pair devices, or pick what syncs —
# that is two clicks in the GUI, and doing it for you would mean writing a
# config file that the GUI then fights over.
#
# The GNOME/Plasma tray indicator is a personal pick (personal overlay /
# extension), not part of this.
#
# Usage: install-sync.sh [--no-service] [--status]
set -euo pipefail

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

take_service=1
mode=apply
for arg in "$@"; do
  case "$arg" in
    --no-service) take_service=0 ;;
    --status) mode=status ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

unit="syncthing@${real_user}.service"

# Config lives in one of two places depending on the version: 2.x moved to
# XDG_STATE_HOME, 1.x used ~/.config.
config_file() {
  local candidate
  for candidate in \
    "$real_home/.local/state/syncthing/config.xml" \
    "$real_home/.config/syncthing/config.xml"; do
    [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

device_id() {
  local cfg
  cfg="$(config_file)" || return 1
  sed -n 's/.*<device id="\([^"]*\)".*/\1/p' "$cfg" | head -n1
}

if [[ "$mode" == status ]]; then
  printf 'syncthing   : %s\n' "$(command -v syncthing >/dev/null 2>&1 && echo installed || echo MISSING)"
  printf 'service     : %s\n' "$(systemctl is-enabled "$unit" >/dev/null 2>&1 && systemctl is-active "$unit" 2>/dev/null || echo 'not enabled')"
  if id="$(device_id)"; then printf 'device id   : %s\n' "$id"; fi
  printf 'web gui     : http://127.0.0.1:8384\n'
  exit 0
fi

if ! command -v syncthing >/dev/null 2>&1; then
  echo "installing syncthing ..."
  as_root pacman -S --needed --noconfirm syncthing
else
  echo "syncthing: already installed"
fi

if (( take_service )); then
  echo "enabling $unit"
  as_root systemctl enable --now "$unit"
  # The daemon writes its config on first start; give it a moment so the device
  # ID below is not empty on a fresh install.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    config_file >/dev/null 2>&1 && break
    sleep 1
  done
fi

echo
echo "==> Syncthing is running: http://127.0.0.1:8384"
if id="$(device_id)"; then
  printf '    this machine device ID:\n      %s\n' "$id"
else
  echo "    device ID: not written yet — open the GUI and look under Actions → Show ID"
fi
cat <<'STEPS'

    Pair two machines (same steps as Bluefin's Sync Folder):
      1. both: open the GUI, Actions → Show ID, leave it open
      2. on B: Add Remote Device → paste A's ID → Save
      3. on A: accept the prompt (Add Device)
      4. either: edit the folder (e.g. ~/Sync) → Sharing → tick the other
         machine → Save, then accept the share prompt on the other side

    Common bits:  ~/Sync, Syncthing Tray / gnome-shell indicator are personal
    picks; the service is what this recipe manages.
STEPS
