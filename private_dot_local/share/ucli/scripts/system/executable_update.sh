#!/usr/bin/env bash
# Update everything: pacman, AUR, Flatpaks, mise runtimes, then the dev box.
#
# One implementation, three callers:
#   ucli update                     full output, asks before the AUR part
#   ucli update --level minimal     one ✓/✗ line per step, failures keep the log
#   ucli update --level prompt      asks before every step
#   ucli update-timer on            a systemd timer runs it with --scheduled
#
# Flags:
#   --level full|minimal|prompt   how much to say (default: full)
#   --no-snapshot                 no restore point before the upgrade (also
#                                 UCLI_NO_SNAPSHOT=1)
#   --scheduled                   what the timer uses: no prompts, no AUR, no dev
#                                 box, minimal output. AUR rebuilds need a human.
#   --help
#
# Exit status: 0 when every step it attempted worked, 1 when one failed (the log
# tail is printed for the failed step, and the remaining steps still run — a
# failed Flatpak update must not leave pacman half-done for the next boot).
set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

level="full"
take_snapshot=1
scheduled=0

usage() {
  cat <<'USAGE'
usage: update.sh [--level full|minimal|prompt] [--no-snapshot] [--scheduled]

Upgrade pacman, the AUR (interactive only), Flatpaks, mise runtimes and the dev
box. A Snapper snapshot is taken first (--no-snapshot / UCLI_NO_SNAPSHOT=1 skips).

  --level full      every command's output (default)
  --level minimal   one ✓/✗ line per step, log tail on failure
  --level prompt    ask before each step
  --scheduled       the timer's mode: no prompts, repo packages + Flatpaks only
USAGE
}

while (($#)); do
  case "$1" in
    --level) level="${2:-}"; shift 2 ;;
    --level=*) level="${1#*=}"; shift ;;
    --no-snapshot) take_snapshot=0; shift ;;
    --scheduled) scheduled=1; level="minimal"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
case "$level" in
  full|minimal|prompt) ;;
  *) echo "--level must be full, minimal or prompt (got '$level')" >&2; exit 2 ;;
esac
[[ "${UCLI_NO_SNAPSHOT:-0}" == "1" ]] && take_snapshot=0

failed=0

# run_step <label> <command...>
run_step() {
  local label="$1"; shift
  ui_rule "$label"
  if [[ "$level" == prompt ]] && ui_tty; then
    ui_confirm "Run: $label?" || { echo "skipped: $label"; return 0; }
  fi
  if [[ "$level" == full ]]; then
    "$@" || { ui_fail "$label"; failed=1; }
    return 0
  fi
  local log rc
  log="$(mktemp -t ucli-update.XXXXXX)"
  "$@" >"$log" 2>&1
  rc=$?
  if (( rc == 0 )); then
    ui_ok "$label"
  else
    ui_fail "$label (exit $rc)"
    printf '  last lines:\n'
    # tail first, then delete: the log is the only explanation of the failure.
    tail -n 15 "$log" 2>/dev/null | sed 's/^/    /' || true
    failed=1
  fi
  rm -f "$log"
  return 0
}

# Restore point first: an upgrade is the one routine thing that can leave a
# machine unbootable, and snapper is already configured with `ucli
# setup-snapshots`. snap-pac also snapshots each pacman transaction, but this one
# is named, so it is findable in the boot menu.
if (( take_snapshot )); then
  ui_rule "snapshot: before update"
  sudo "$script_dir/snapshot-fresh-install.sh" "before update" \
    || echo "warning: could not take a restore point; continuing" >&2
fi

# Guard, ported from `ujust update`: Bluefin refuses to update while the image has
# layered packages, because that breaks its zero-maintenance promise. The Arch
# equivalent of "layered" is foreign (AUR / locally built) packages: they can need
# a rebuild or an upstream fix mid-upgrade, so show them first and ask. UCLI_YES=1
# or a non-interactive run proceeds; --scheduled skips the AUR step entirely.
if (( ! scheduled )) && ui_have pacman; then
  foreign="$(pacman -Qm 2>/dev/null || true)"
  if [[ -n "$foreign" ]]; then
    n="$(printf '%s\n' "$foreign" | wc -l | tr -d ' ')"
    ui_rule "foreign / AUR packages: $n"
    printf '%s\n' "$foreign" | awk 'NR<=10 { printf "    %s\n", $0 }'
    (( n > 10 )) && printf '    … and %s more\n' "$((n - 10))"
    printf '    Not from the official repos: AUR rebuilds are your responsibility.\n'
    if [[ "${UCLI_YES:-0}" != 1 ]] && ui_tty; then
      ui_confirm "Continue with the upgrade?" || { printf 'aborted.\n'; exit 1; }
    fi
  fi
fi

run_step "pacman: system upgrade" sudo pacman -Syu --noconfirm

if (( scheduled )); then
  ui_rule "AUR: skipped (scheduled run — rebuilds need a human)"
elif ui_have paru; then
  run_step "paru: AUR upgrades" paru -Sua --noconfirm
elif ui_have yay; then
  run_step "yay: AUR upgrades" yay -Sua --noconfirm
fi

# Flatpaks: a system-wide update covers /var/lib/flatpak; the per-user ones live in
# ~/.local/share/flatpak and need the user's own session, which the timer (running
# as root) reaches through UCLI_TIMER_USER.
flatpak_update() {
  flatpak update -y || return 1
  if (( EUID == 0 )) && [[ -n "${UCLI_TIMER_USER:-}" ]]; then
    runuser -u "$UCLI_TIMER_USER" -- flatpak update -y || \
      printf 'warning: user Flatpaks not updated (flatpak as %s failed)\n' "$UCLI_TIMER_USER" >&2
  fi
}
ui_have flatpak && run_step "flatpak: updates" flatpak_update
ui_have mise && run_step "mise: runtimes" mise upgrade

if (( scheduled )); then
  ui_rule "dev box: skipped (scheduled run)"
elif [[ -x "$HOME/.local/share/ucli/scripts/devbox/devbox-reconcile.sh" ]]; then
  run_step "dev box" "$HOME/.local/share/ucli/scripts/devbox/devbox-reconcile.sh"
else
  ui_rule "dev box: skipped (devbox-reconcile.sh not found)"
fi

# A reboot is needed when the running kernel no longer has a module tree — the
# one reliable signal, and cheaper than parsing pacman's log.
if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
  ui_rule "reboot needed (kernel changed)"
fi

if (( failed )); then
  ui_rule "done: something failed"
  exit 1
fi
ui_rule "done"
printf 'A reboot is only needed for kernel/driver updates.\n'
