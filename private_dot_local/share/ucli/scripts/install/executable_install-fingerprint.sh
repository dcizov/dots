#!/usr/bin/env bash
# Fingerprint reader: make it usable from the desktop's own Settings UI.
#
# A fingerprint reader needs three things, and only one of them is a package:
#   1. fprintd (the daemon that owns the device) — installed here
#   2. an enrollment — done in the DE's Settings, which is the point of this
#      script: GNOME and Plasma both ship a fingerprint page that talks to
#      fprintd, so there is no reason to make you run fprintd-enroll by hand
#   3. PAM, only if you want the finger to unlock the screen, sudo and the
#      display manager — opt-in via --pam, because editing /etc/pam.d by hand
#      is the one change in this repo that can lock you out
#
# The reader is detected the same way `install-packages.sh hardware` does it
# (USB ids from lib/detect.sh); --force skips the check for a reader that
# enumerates unusually.
#
# Usage: install-fingerprint.sh [--status] [--enroll] [--pam] [--force] [--yes]
set -euo pipefail

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

mode=apply
take_pam=0
force=0
yes_flag=0
for arg in "$@"; do
  case "$arg" in
    --status) mode=status ;;
    --enroll) mode=enroll ;;
    --pam) take_pam=1 ;;
    --force) force=1 ;;
    --yes|-y) yes_flag=1 ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

pam_file="/etc/pam.d/system-auth"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../lib/common.sh"

has_reader() {
  # lib/detect.sh knows the vendor/product ids (138a, 06cb, 27c6, 08ff, 0483)
  local lib="$real_home/.local/share/ucli/scripts/lib/detect.sh"
  if [[ -r "$lib" ]]; then
    # shellcheck source=/dev/null
    source "$lib"
    [[ "$(detect_fingerprint 2>/dev/null || echo no)" == yes ]]
    return
  fi
  have lsusb || return 1
  lsusb 2>/dev/null | grep -Eiq '138a:|06cb:|27c6:|08ff:|0483:'
}

pam_wired() { [[ -r "$pam_file" ]] && grep -q 'pam_fprintd' "$pam_file"; }

enrolled_fingers() {
  have fprintd-list || return 1
  as_root fprintd-list "$real_user" 2>/dev/null \
    | sed -n 's/^.*: \(.*\)$/\1/p' | tr '\n' ' '
}

desktop_name() {
  local lib="$real_home/.local/share/ucli/scripts/lib/detect.sh"
  if [[ -r "$lib" ]]; then
    # shellcheck source=/dev/null
    source "$lib"
    detect_desktop 2>/dev/null || echo none
  else
    echo none
  fi
}

# Prints the desktop's own enrollment page. Named enroll_hint, not ui_hint:
# ui_hint is the shared dim one-liner in lib/ui.sh.
enroll_hint() {
  case "$(desktop_name)" in
    gnome) cat <<'GNOME'
    GNOME:  Settings → System → Users → Unlock → Fingerprint Login → + Add Fingerprint
GNOME
    ;;
    kde|plasma) cat <<'KDE'
    Plasma: System Settings → Users → Fingerprint (Plasma 6) → Enroll
            (no fingerprint page? Plasma versions before 6.1 have none — use
             `ucli fingerprint --enroll`)
KDE
    ;;
    *) cat <<'OTHER'
    This desktop has no fingerprint page, so enroll from the terminal:
      ucli fingerprint --enroll
OTHER
    ;;
  esac
}

if [[ "$mode" == status ]]; then
  printf 'reader      : %s\n' "$(has_reader && echo found || echo 'none detected')"
  printf 'fprintd     : %s\n' "$(have fprintd && echo installed || echo MISSING)"
  printf 'service     : %s\n' "$(systemctl is-active fprintd.service 2>/dev/null || echo inactive)"
  if have fprintd && have fprintd-list; then
    fingers="$(enrolled_fingers || true)"
    printf 'enrolled    : %s\n' "${fingers:-none}"
  fi
  printf 'PAM (system-auth): %s\n' "$(pam_wired && echo 'wired (login, sudo, unlock)' || echo 'not wired (--pam)')"
  echo
  enroll_hint
  exit 0
fi

if [[ "$mode" == enroll ]]; then
  if ! have fprintd-enroll; then
    echo "fprintd is not installed — run 'ucli fingerprint' first" >&2
    exit 1
  fi
  echo "Enroll a finger for $real_user (swipe the same finger several times) ..."
  # fprintd-enroll talks to the daemon over D-Bus and needs the device; run it as
  # the user who will log in, not as root.
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    runuser -u "$real_user" -- fprintd-enroll || true
  else
    fprintd-enroll || true
  fi
  echo
  echo "enrolled: $(enrolled_fingers || echo 'none')"
  exit 0
fi

# ---------------------------------------------------------------- apply -----

if has_reader; then
  echo "fingerprint reader: found"
elif (( force )); then
  echo "fingerprint reader: not detected, continuing (--force)"
else
  cat <<'NOREADER' >&2
No fingerprint reader found on this machine, so there is nothing to install.
  If the reader does exist (some are behind a hub, or report an unusual id):
    ucli fingerprint --force
NOREADER
  exit 0
fi

echo "installing fprintd ..."
if have fprintd; then
  echo "  fprintd: already installed"
else
  args=(-S --needed)
  (( yes_flag )) && args+=(--noconfirm)
  as_root pacman "${args[@]}" fprintd
fi

# fprintd is D-Bus activated, so "start" is all it needs; enabling the unit too
# costs nothing and keeps `--status` honest after a reboot.
as_root systemctl enable --now fprintd.service 2>/dev/null || \
  echo "  note: fprintd will be started on demand by D-Bus" >&2

if (( take_pam )); then
  if pam_wired; then
    echo "PAM: pam_fprintd already present in $pam_file"
  else
    backup="$pam_file.ucli-backup"
    if [[ ! -e "$backup" ]]; then
      as_root cp -a "$pam_file" "$backup"
      echo "PAM: backup written to $backup"
    fi
    # "sufficient" after pam_unix means: password still works, and the finger is
    # tried as an alternative. On the wrong side of pam_unix it would stop the
    # password from being asked for.
    as_root python3 - "$pam_file" <<'PY'
import os, sys

path = sys.argv[1]
with open(path) as handle:
    lines = handle.readlines()
out, inserted = [], False
for line in lines:
    out.append(line)
    fields = line.split()
    if (not inserted and fields and fields[0] == "auth"
            and any("pam_unix.so" in field for field in fields)):
        out.append("auth      sufficient  pam_fprintd.so\n")
        inserted = True
if not inserted:
    sys.stderr.write("no 'auth ... pam_unix.so' line found; %s left untouched\n" % path)
    sys.exit(1)
tmp = path + ".ucli-new"
with open(tmp, "w") as handle:
    handle.write("".join(out))
os.replace(tmp, path)
PY
    echo "PAM: added 'auth sufficient pam_fprintd.so' after pam_unix"
    echo "     (test it: lock the screen and unlock with the finger, and keep a"
    echo "      root shell open until you have — $backup is the way back)"
  fi
fi

echo
echo "==> fingerprint reader ready"
enroll_hint
cat <<'NOTES'

    Notes:
      - enrollment is per user; the finger enrolled here is $USER's
      - without PAM the finger only works for apps that ask fprintd directly
        (and for the enrollment test in Settings) — `ucli fingerprint --pam`
        wires login, screen unlock and sudo
      - `ucli fingerprint --status` shows reader, service, enrolled fingers and
        whether PAM is wired
NOTES
