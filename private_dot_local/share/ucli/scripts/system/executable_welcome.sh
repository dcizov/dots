#!/usr/bin/env bash
# The front door: what this machine is, what is pending, what to do next.
#
# This is the piece CachyOS Hello gets from a GUI window and ujust gets from
# `ujust` with no arguments (a list). Here it is one screen that answers four
# questions in four lines, then points at the recipes that matter:
#
#   1. what is deployed (repo commit, desktop, dotfile drift)
#   2. what is pending (package updates, reboot)
#   3. how old the last restore point is
#   4. what to run next, if anything
#
#   ucli welcome                 the full screen
#   ucli welcome --status        the four-line version (also the `ucli` menu header)
#   ucli welcome --first-login   the same, once per machine (version gate)
#
# Read-only: it never installs, applies or changes anything except its own
# first-login gate. No sudo, no network — `pacman -Qu` reads the local sync
# database, so this prints instantly.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"
# shellcheck source=/dev/null
. "$script_dir/../lib/version-script.sh"

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

mode="full"
while (($#)); do
  case "$1" in
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --status) mode="status" ;;
    --full) mode="full" ;;
    --first-login) mode="first-login" ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# --- the four facts ---------------------------------------------------------

repo_commit() {
  local out
  out="$(git -C "$real_home/.local/share/chezmoi" log --oneline -1 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    printf '%s\n' "${out%% *}"
  else
    printf 'not deployed\n'
  fi
}

repo_drift() {
  ui_have chezmoi || return 0
  local n
  n="$(chezmoi status 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s\n' "${n:-0}"
}

pending_updates() {
  # No pacman database means this is not an Arch box (or not readable as this
  # user): say "?" rather than "0", which would be a lie.
  if [[ ! -r /var/lib/pacman/local ]]; then printf '?\n'; return 0; fi
  pacman -Qu 2>/dev/null | wc -l | tr -d ' '
}

last_snapshot() {
  local f="/etc/ucli/installation-snapshot" id age
  [[ -r "$f" ]] || { printf 'none\n'; return 0; }
  id="$(cat "$f" 2>/dev/null || echo '?')"
  local mtime now
  mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  age="$(_age $(( now - mtime )))"
  printf '#%s, %s ago\n' "$id" "$age"
}

_age() {
  local s="${1:-0}"
  (( s < 0 )) && s=0
  if (( s < 90 )); then printf '%ds' "$s"
  elif (( s < 5400 )); then printf '%dm' "$(( s / 60 ))"
  elif (( s < 172800 )); then printf '%dh' "$(( s / 3600 ))"
  else printf '%dd' "$(( s / 86400 ))"; fi
}

reboot_needed() {
  [[ -d "/usr/lib/modules/$(uname -r)" ]] || { printf 'yes (kernel changed)\n'; return 0; }
  printf 'no\n'
}

desktop_name() {
  local d="${XDG_CURRENT_DESKTOP:-}"
  if [[ -z "$d" ]]; then
    if [[ -n "${SSH_CONNECTION:-}" ]]; then printf 'none (SSH)\n'
    else printf 'none (console)\n'; fi
    return 0
  fi
  printf '%s\n' "${d%%:*}"
}

tweaks_on() {
  local packages_bash="$real_home/.config/ucli/packages.bash" entry n unit kind on=0 total=0
  [[ -r "$packages_bash" ]] || { printf 'n/a\n'; return 0; }
  # shellcheck source=/dev/null
  . "$packages_bash"
  declare -p TWEAKS >/dev/null 2>&1 || { printf 'n/a\n'; return 0; }
  for entry in "${TWEAKS[@]}"; do
    IFS='|' read -r n unit _ kind _ <<<"$entry"
    if [[ "$kind" == template && "$unit" == *"@."* ]]; then
      unit="${unit%%@.*}@${real_user}.${unit##*@.}"
    fi
    total=$(( total + 1 ))
    systemctl is-enabled --quiet "$unit" >/dev/null 2>&1 && on=$(( on + 1 ))
  done
  printf '%s/%s\n' "$on" "$total"
}

status_block() {
  local drift
  drift="$(repo_drift)"
  printf '  %-9s %s · repo %s%s\n' "machine" "$(desktop_name)" "$(repo_commit)" \
    "$([[ "${drift:-0}" != 0 ]] && printf ' (%s file(s) out of sync)' "$drift")"
  local pending
  pending="$(pending_updates)"
  if [[ "$pending" =~ ^[0-9]+$ ]]; then
    printf '  %-9s %s package update(s)\n' "pending" "$pending"
  else
    printf '  %-9s unknown (no pacman database as this user)\n' "pending"
  fi
  printf '  %-9s %s\n' "snapshot" "$(last_snapshot)"
  printf '  %-9s %s\n' "reboot" "$(reboot_needed)"
}

next_steps() {
  local steps=() missing
  if [[ ! -d "$real_home/.local/share/chezmoi" ]]; then
    steps+=("bootstrap — the repo is not deployed yet (run install.sh)")
  fi
  [[ "$(desktop_name)" == none* && -d "$real_home/.local/share/chezmoi" ]] && \
    steps+=("ucli setup-system gnome — no desktop session yet")
  if [[ -x "$real_home/.local/share/ucli/scripts/check/doctor.sh" ]]; then
    missing="$("$real_home/.local/share/ucli/scripts/check/doctor.sh" 2>/dev/null | grep -c 'MISSING' || true)"
    if [[ "${missing:-0}" -gt 0 ]]; then
      steps+=("ucli doctor — ${missing} thing(s) missing")
    fi
  fi
  local pending
  pending="$(pending_updates)"
  if [[ "$pending" =~ ^[0-9]+$ ]] && (( pending > 0 )); then
    steps+=("ucli update — ${pending} update(s) waiting")
  fi
  if [[ ! -r "$real_home/.local/state/ucli/devmode" && -d "$real_home/.local/share/chezmoi" ]]; then
    steps+=("ucli devmode — optional developer tooling")
  fi
  steps+=("ucli tweak list — turn a service on or off (bluetooth, cups, fstrim, …)")
  steps+=("ucli dns set cloudflare — a DNS preset for the active connection")

  ui_rule "next"
  local s
  for s in "${steps[@]}"; do
    printf '  · %s\n' "$s"
  done
}

full_screen() {
  ui_title "ucli — $(hostname 2>/dev/null || echo machine)"
  status_block
  echo
  printf '  %-9s %s\n' "tweaks" "$(tweaks_on) enabled (ucli tweak list)"
  echo
  next_steps
  echo
  ui_rule "docs"
  printf '  '
  ui_link "https://github.com/dcizov/dots/blob/main/docs/operations.md" "operations"
  printf ' · '
  ui_link "https://github.com/dcizov/dots/blob/main/docs/getting-started.md" "getting started"
  printf ' · '
  ui_link "https://github.com/dcizov/dots" "repo"
  printf '\n'
  printf '  %s\n' "ucli usage — every recipe · ucli --choose — fuzzy picker"
}

case "$mode" in
  status) status_block ;;
  full) full_screen ;;
  first-login)
    # Once per machine: the version gate lives in the XDG state dir and is
    # committed only after the screen printed, so an interrupted login shows it
    # again next time.
    if vs_check welcome user 1; then
      ui_rule "welcome"
      status_block
      echo
      next_steps
      vs_commit welcome user 1
    fi
    ;;
esac
