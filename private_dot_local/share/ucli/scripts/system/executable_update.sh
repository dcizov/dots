#!/usr/bin/env bash
# Update everything: pacman, AUR, Flatpaks, mise runtimes, then the dev box.
#
# One implementation, three callers:
#   ucli update                     full output, asks before the AUR part
#   ucli update --level minimal     one ✓/✗ line per step, failures keep the log
#   ucli update --level prompt      asks before every step
#   ucli update-timer on            a systemd timer runs it with --scheduled
#
# The AUR is paru or shelly, never yay: this repo installs only those two
# (AUR_HELPER in packages.bash, empty = shelly if installed, else paru) and
# nothing else on the machine calls yay, so driving a third helper here would be
# an untested path. `--scheduled` (the timer) never touches the AUR at all.
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

# "Nobody is watching" is what turns confirmations off — a missing terminal, or
# UCLI_YES=1 from a script. Interactive runs keep pacman's own prompts (replace /
# conflict questions) and the AUR helper's PKGBUILD review: those are the only two
# places where an upgrade asks you something worth reading.
auto=0
if ! ui_tty || [[ "${UCLI_YES:-0}" == 1 ]]; then auto=1; fi

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

# --- the AUR helper ---------------------------------------------------------
# Both files are plain assignments (install-aur-helper.sh sources them the same
# way); the subshell keeps their arrays out of the updater's own namespace.
configured_helper() {
  local cfg
  (
    AUR_HELPER="${AUR_HELPER:-}"
    for cfg in "$HOME/.config/ucli/packages.bash" "$HOME/.config/ucli/packages.local.bash"; do
      [[ -r "$cfg" ]] || continue
      # shellcheck source=/dev/null
      . "$cfg"
    done
    printf '%s' "${AUR_HELPER:-}"
  )
}

# The configured helper wins when it is actually installed, otherwise the first
# one that is. Empty output means nothing here can rebuild AUR packages.
aur_helper() {
  local want
  want="$(configured_helper)"
  if [[ -n "$want" ]] && ui_have "$want"; then printf '%s' "$want"; return 0; fi
  if ui_have shelly; then printf 'shelly'; elif ui_have paru; then printf 'paru'; fi
}

# aur_upgrade <helper> <auto:0|1>
# auto=1 means nobody is at the keyboard, so the confirmation is skipped — and
# with it the PKGBUILD diff, which is the only reason to watch an AUR build.
# shelly reads stdin and declines on its own when it cannot ask, so it needs the
# flag as much as paru does.
aur_upgrade() {
  local helper="$1" auto="$2"
  case "$helper" in
    paru) if (( auto )); then paru -Sua --noconfirm; else paru -Sua; fi ;;
    shelly) if (( auto )); then shelly upgrade aur --no-confirm; else shelly upgrade aur; fi ;;
    *) printf 'unknown AUR helper: %s\n' "$helper" >&2; return 2 ;;
  esac
}

# mise keeps its runtimes in $HOME, so the timer (running as root) has to borrow
# the user's identity — exactly like the per-user Flatpaks. mise itself is a repo
# package, so root's PATH resolves it; only HOME has to be handed over.
mise_upgrade() {
  if (( EUID == 0 )) && [[ -n "${UCLI_TIMER_USER:-}" ]]; then
    local home
    home="$(getent passwd "$UCLI_TIMER_USER" | cut -d: -f6)"
    if [[ -z "$home" ]]; then
      printf 'warning: no home for %s; mise not updated\n' "$UCLI_TIMER_USER" >&2
      return 0
    fi
    runuser -u "$UCLI_TIMER_USER" -- env HOME="$home" mise upgrade
  else
    mise upgrade
  fi
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

if (( auto )); then
  run_step "pacman: system upgrade" sudo pacman -Syu --noconfirm
else
  run_step "pacman: system upgrade" sudo pacman -Syu
fi

if (( scheduled )); then
  ui_rule "AUR: skipped (scheduled run — rebuilds need a human)"
else
  helper="$(aur_helper)"
  if [[ -z "$helper" ]]; then
    # Never let this be silent: on a box where the helper is missing the AUR half
    # of the system would otherwise drift with no hint in the output.
    ui_rule "AUR: skipped (no paru or shelly installed — nothing to rebuild with)"
  else
    if (( auto )); then
      printf 'AUR: unattended — the PKGBUILD review prompt is skipped.\n'
    fi
    run_step "$helper: AUR upgrades" aur_upgrade "$helper" "$auto"
  fi
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
ui_have mise && run_step "mise: runtimes" mise_upgrade

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
