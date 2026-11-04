#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# Args: an optional desktop name, plus the flags shared by the machine-setup steps.
#   --no-snapshot   no restore point before or after (also UCLI_NO_SNAPSHOT=1)
#   --yes           assume yes for the preflight question
#   --force         re-run the gated Firefox steps in the desktop step
desktop=""
take_snapshot=1
firefox_force=0
for arg in "$@"; do
  case "$arg" in
    --no-snapshot) take_snapshot=0 ;;
    --yes|-y) UCLI_YES=1 ;;
    --force) firefox_force=1 ;;
    --help|-h)
      cat <<'EOF'
usage: install-profile.sh [--no-snapshot] [--yes] [--force] [gnome|kde|hyprland]

The machine step: base packages, then the desktop step (DE, firefox + terminal,
shell tier, dotfiles, GNOME extensions, Firefox profile, snapshot).

  --no-snapshot   skip every Snapper snapshot of this run (UCLI_NO_SNAPSHOT=1 too)
  --yes           do not ask when there is no snapper config
  --force         re-run the gated Firefox steps (Betterfox copy, GNOME theme)
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
source "$real_home/.local/share/ucli/scripts/lib/detect.sh"


# Preflight: the desktop step is the destructive one (packages, chsh, a snapshot
# at the end), so on a machine with no snapper config warn and — on a TTY — ask.
# Same rule as `ucli update`: a pipe/non-TTY proceeds, UCLI_YES=1 proceeds.
if [[ ! -f /etc/snapper/configs/root ]] && [[ "$UCLI_NO_SNAPSHOT" != "1" ]]; then
  echo "warning: no Snapper config found — the desktop step will not be able to"
  echo "         create a restore point first. 'ucli setup-snapshots' sets it up."
  if [[ -t 0 && "${UCLI_YES:-0}" != "1" ]]; then
    if ! ui_confirm "Continue without snapshots?"; then
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

# Each step names itself and reports its own failure. Before this, a step that
# exited 1 without a message surfaced as `error: recipe `setup-system` failed on
# line 5`, with no way to tell which of the three it was.
run_step() {
  local label="$1" hint="$2"
  shift 2
  ui_rule "$label"
  local rc=0
  "$@" || rc=$?
  if (( rc != 0 )); then
    ui_fail "$label failed (exit $rc)"
    printf '  %s\n' "$hint" >&2
    exit "$rc"
  fi
}

# base = the machine itself: bootstrap, cpu/gpu, system tools, fonts, ucli runtime.
run_step "base packages" \
  "fix the error above, then re-run: ucli setup-system${desktop:+ $desktop}" \
  "$script_dir/install-packages.sh" base

run_step "base flatpaks" \
  "fix the error above, then re-run: ucli setup-system${desktop:+ $desktop}" \
  "$script_dir/install-flatpaks.sh" base

# The desktop is one owner: setup-desktop.sh installs the DE with the
# replacement matrix, adds ghostty + firefox, installs/enables the GNOME
# extensions and takes a snapshot. Pass the desktop as $1 ("gnome", "kde",
# "hyprland") or leave it empty to let it auto-detect/prompt.
desktop_args=()
[[ -n "$desktop" ]] && desktop_args+=("$desktop")
(( take_snapshot )) || desktop_args+=(--no-snapshot)
(( firefox_force )) && desktop_args+=(--force)
if [[ -x "$script_dir/setup-desktop.sh" ]]; then
  run_step "desktop${desktop:+ ($desktop)}" \
    "fix the error above, then re-run: sudo ucli setup-desktop${desktop:+ $desktop}" \
    sudo "$script_dir/setup-desktop.sh" ${desktop_args[@]+"${desktop_args[@]}"}
else
  echo "warning: setup-desktop.sh missing; install the desktop yourself" >&2
fi

ui_rule "setup-system done"
ui_note "next: ucli cli   then   ucli apps   (re-login when both are done)"