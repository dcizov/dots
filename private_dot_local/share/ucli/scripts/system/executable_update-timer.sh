#!/usr/bin/env bash
# Unattended upgrades on a schedule — the "update in the background" switch that
# Bluefin gets from uupd and ujust exposes as a timer.
#
#   ucli update-timer status
#   sudo ucli update-timer on            daily, with up to an hour of jitter
#   sudo ucli update-timer on --time 04:30
#   sudo ucli update-timer off
#
# What the timer runs: `update.sh --scheduled` — repo packages, Flatpaks (system
# and the invoking user's), mise, plus the usual restore point. What it does NOT
# run: AUR upgrades and the dev box. AUR builds need a human at the prompt
# (makepkg refuses root, and a half-built AUR package mid-upgrade is exactly the
# failure mode `ucli update` warns about), so they stay manual by design.
#
# State lives in systemd, the unit files live in /etc/systemd/system and are
# written here: `systemctl is-enabled ucli-update.timer` is the answer to "is it
# on", so there is no state file to drift.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

action=""
time_spec="daily"
dry_run=0
while (($#)); do
  case "$1" in
    on|off|status) action="$1"; shift ;;
    --time) time_spec="${2:-daily}"; shift 2 ;;
    --time=*) time_spec="${1#*=}"; shift ;;
    --dry-run|-n) dry_run=1; shift ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
action="${action:-status}"

if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Run as root: sudo ucli update-timer on|off" >&2
  exit 1
fi

unit_dir="${UCLI_TEST_ROOT:-}/etc/systemd/system"
service="ucli-update.service"
timer="ucli-update.timer"
update_script="$real_home/.local/share/ucli/scripts/system/update.sh"

# OnCalendar accepts "daily" and "HH:MM".
oncalendar="daily"
if [[ "$time_spec" != "daily" ]]; then
  [[ "$time_spec" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || {
    echo "--time takes daily or HH:MM (got '$time_spec')" >&2; exit 2; }
  oncalendar="*-*-* ${time_spec}:00"
fi

write_units() {
  local svc="$unit_dir/$service" tmr="$unit_dir/$timer"
  local svc_body tmr_body
  svc_body="$(cat <<EOF
[Unit]
Description=Scheduled upgrade: repo packages + Flatpaks (written by ucli)
Documentation=file://$real_home/.local/share/ucli/scripts/system/update.sh
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=UCLI_TIMER_USER=$real_user
Environment=UCLI_NO_SNAPSHOT=0
ExecStart=$update_script --scheduled
Nice=10
IOSchedulingClass=idle
EOF
)"
  tmr_body="$(cat <<EOF
[Unit]
Description=Daily system upgrade (ucli)

[Timer]
OnCalendar=$oncalendar
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
)"

  printf '+ write %s\n' "$svc"
  printf '+ write %s\n' "$tmr"
  if (( dry_run )); then
    printf '\n%s\n\n%s\n' "$svc_body" "$tmr_body"
    return 0
  fi
  mkdir -p "$unit_dir"
  printf '%s\n' "$svc_body" >"$svc"
  printf '%s\n' "$tmr_body" >"$tmr"
  chmod 644 "$svc" "$tmr"
}

timer_state() {
  local state
  # is-enabled prints "enabled"/"disabled"/"static" and exits 0 for a unit it
  # knows; for one it does not, it exits non-zero. Use the status, not the text.
  if state="$(systemctl is-enabled "$timer" 2>/dev/null)"; then
    printf '%s\n' "${state:-enabled}"
  else
    printf 'not installed\n'
  fi
}

case "$action" in
  status)
    ui_rule "ucli update timer"
    printf '  state:   %s\n' "$(timer_state)"
    if systemctl list-timers "$timer" --no-legend >/dev/null 2>&1; then
      systemctl list-timers "$timer" --no-legend 2>/dev/null | sed 's/^/  /'
    fi
    printf '  last:    %s\n' "$(systemctl show -p Result --value "$service" 2>/dev/null || echo 'never run')"
    printf '  scope:   repo packages + Flatpaks + snapshot; AUR and the dev box stay manual\n'
    ;;
  on)
    [[ -x "$update_script" ]] || { echo "no $update_script (run the bootstrap)" >&2; exit 1; }
    ui_rule "installing the update timer ($time_spec)"
    write_units
    if (( dry_run )); then
      printf '+ systemctl daemon-reload\n+ systemctl enable --now %s\n' "$timer"
      exit 0
    fi
    systemctl daemon-reload
    systemctl enable --now "$timer"
    ui_ok "$timer enabled"
    systemctl list-timers "$timer" --no-legend 2>/dev/null | sed 's/^/  /'
    printf '  turn it off with: sudo ucli update-timer off\n'
    ;;
  off)
    ui_rule "removing the update timer"
    if [[ "$(timer_state)" == "not installed" ]] && [[ ! -e "$unit_dir/$timer" ]]; then
      printf '  not installed — nothing to do\n'
      exit 0
    fi
    if (( dry_run )); then
      printf '+ systemctl disable --now %s\n+ rm %s %s\n+ systemctl daemon-reload\n' \
        "$timer" "$unit_dir/$service" "$unit_dir/$timer"
      exit 0
    fi
    systemctl disable --now "$timer" 2>/dev/null || true
    rm -f "$unit_dir/$service" "$unit_dir/$timer"
    systemctl daemon-reload
    ui_ok "timer removed"
    ;;
  *) echo "usage: update-timer.sh [on|off|status] [--time daily|HH:MM]" >&2; exit 2 ;;
esac
