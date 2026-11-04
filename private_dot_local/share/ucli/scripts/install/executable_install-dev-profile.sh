#!/usr/bin/env bash
# install-dev-profile.sh — `ucli devmode`: the developer-mode setup wizard.
#
# Modelled on Bluefin's `ujust devmode` (projectbluefin/common, system.just
# `toggle-devmode`):
#
#   * gum title banner and one `gum choose --no-limit` screen as the whole
#     questionnaire instead of a pile of separate prompts, with the categories
#     (toolchain / apps / containers) as the left-hand column — not as heading
#     rows, because gum cannot render a row you cannot toggle,
#   * summary box + confirmation before anything runs,
#   * block-character progress bar with per-step ✓/✗,
#   * a marker file so a re-run offers "already set up, add more tools?" and
#     preselects whatever was installed last time,
#   * nothing here needs a reboot.
#
# Usage:
#   install-dev-profile.sh            # wizard on a TTY, everything otherwise
#   install-dev-profile.sh --all      # install every item, no menu
#   install-dev-profile.sh --yes      # skip the confirmation
#   install-dev-profile.sh --status   # show marker + version gate state
#   install-dev-profile.sh --reset    # forget marker/gate, wizard next time
#
# Non-interactive callers (CI, piped output) get --all behaviour.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# The UI layer ships next to the scripts (../lib), so it resolves from this
# file's own path even when the script runs under sudo.
# shellcheck source=/dev/null
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../lib" && pwd)/ui.sh"
# shellcheck source=/dev/null
. "$real_home/.config/ucli/scripts/lib/version-script.sh"

DEVMODE_VERSION=1
state_dir="${XDG_STATE_HOME:-$real_home/.local/state}/ucli"
marker="$state_dir/devmode"

mode=wizard
assume_yes=0
while (($#)); do
  case "$1" in
    --all|-a) mode=all ;;
    --yes|-y) assume_yes=1 ;;
    --status) mode=status ;;
    --reset)  mode=reset ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# --- item catalogue ---------------------------------------------------------

# Display order: "section|id". The section is the left-hand column of the menu,
# not a heading row — gum cannot render a row that cannot be toggled, and a
# heading you can tick but that does nothing (the old "── Toolchain ──" rows)
# was exactly that bug. `label_for` turns an id into the row text.
#
# Labels carry no comma on purpose: gum's --selected is a comma-separated list,
# so one comma in a label silently breaks the "preselect last time's picks".
MENU_LAYOUT=(
  "toolchain|dev-cli"
  "toolchain|dev-pkgs"
  "apps|flatpaks"
  "apps|vscodium"
  "apps|firefox"
  "containers|devbox"
)

item_id() { printf '%s' "${1#*|}" ; }

label_for() {
  case "$1" in
    dev-cli)  printf 'Dev CLI (jq · ripgrep · fd · neovim · tmux · mise …)' ;;
    dev-pkgs) printf 'Dev packages (docker · podman for distrobox · distrobox · vscodium)' ;;
    flatpaks) printf 'Dev flatpaks (podman desktop …)' ;;
    vscodium) printf 'VSCodium extensions' ;;
    firefox)  printf 'Firefox dev extensions (React DevTools)' ;;
    devbox)   printf 'Dev box (Debian distrobox + node + php)' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# Short name for the summary box / marker file.
name_for() {
  case "$1" in
    dev-cli)  printf 'dev CLI packages' ;;
    dev-pkgs) printf 'dev packages' ;;
    flatpaks) printf 'dev flatpaks' ;;
    vscodium) printf 'VSCodium extensions' ;;
    firefox)  printf 'Firefox dev extensions' ;;
    devbox)   printf 'dev box' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# Steps that must succeed. Everything else reports ✗ and the wizard continues.
is_fatal() { [[ "$1" == dev-cli || "$1" == dev-pkgs ]]; }

# Shell command for an item. Kept as a string so `ui_step` can hand it to
# `bash -c`: shell functions do not survive the fork that `gum spin` performs.
cmd_for() {
  local reconcile="$real_home/.local/share/ucli/scripts/devbox/devbox-reconcile.sh"
  case "$1" in
    dev-cli)  printf '%s' "\"$script_dir/install-packages.sh\" dev-cli" ;;
    # docker needs more than the package: the daemon off by default and the
    # group missing is why `docker ps` fails or asks for sudo. podman is left
    # alone on purpose — it is distrobox's rootless backend, nothing else.
    dev-pkgs) printf '%s' "\"$script_dir/install-packages.sh\" --force dev && \"$script_dir/enable-docker-access.sh\"" ;;
    flatpaks) printf '%s' "\"$script_dir/install-flatpaks.sh\" dev" ;;
    vscodium) printf '%s' "command -v codium >/dev/null || { echo 'skipped: codium is not installed'; exit 0; }; \"$script_dir/install-vscodium-extensions.sh\"" ;;
    firefox)  printf '%s' "\"$script_dir/install-firefox-extensions.sh\" \"$real_home/.config/ucli/firefox/dev-extensions.txt\"" ;;
    devbox)   printf '%s' "command -v distrobox >/dev/null || { echo 'skipped: distrobox is not installed'; exit 0; }; [ -x \"$reconcile\" ] || { echo 'skipped: devbox-reconcile.sh not found'; exit 0; }; \"$reconcile\"" ;;
    *)        return 1 ;;
  esac
}

all_ids() {
  local entry
  for entry in "${MENU_LAYOUT[@]}"; do
    printf '%s\n' "${entry#*|}"
  done
}

# --- marker (state, not config: lives in XDG_STATE_HOME) --------------------

marker_value() {
  [[ -r "$marker" ]] || return 0
  sed -n "s/^$1=//p" "$marker" | head -n1
}

marker_items() {
  marker_value items | tr ',' '\n'
}

write_marker() {
  local items
  items="$(IFS=,; printf '%s' "$*")"
  mkdir -p "$state_dir"
  {
    printf 'version=%s\n' "$DEVMODE_VERSION"
    printf 'items=%s\n' "$items"
    printf 'updated=%s\n' "$(date -Iseconds 2>/dev/null || date)"
  } >"$marker"
  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    chown "$real_user" "$marker" 2>/dev/null || true
  fi
}

contains() { # contains <needle> <haystack...>
  local needle="$1" x
  shift
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# --- state modes ------------------------------------------------------------

case "$mode" in
  status)
    if [[ -r "$marker" ]]; then
      printf 'devmode marker: %s\n' "$marker"
      sed 's/^/  /' "$marker"
    else
      printf 'devmode: not configured (no marker at %s)\n' "$marker"
    fi
    printf '\nversion gates:\n'
    gates="$(vs_list)"
    if [[ -n "$gates" ]]; then printf '%s\n' "$gates" | sed 's/^/  /'; else printf '  (none)\n'; fi
    exit 0
    ;;
  reset)
    rm -f "$marker"
    vs_forget devmode user
    printf 'devmode state cleared; the next run starts the wizard from scratch.\n'
    exit 0
    ;;
esac

# --- wizard -----------------------------------------------------------------

ui_title "Turn on Developer Mode"
echo

if [[ -r "$marker" ]]; then
  prev_names=""
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    prev_names+="${prev_names:+, }$(name_for "$id")"
  done < <(marker_items)
  ui_summary "Developer mode is already set up." \
    "last run:  $(marker_value updated)" \
    "installed: ${prev_names:-(nothing yet)}"
  echo
  if [[ "$mode" == wizard ]] && ! ui_confirm "Add more tools?"; then
    exit 0
  fi
fi

selected=()
if [[ "$mode" == all ]]; then
  mapfile -t selected < <(all_ids)
  printf 'installing every devmode item (non-interactive)\n'
else
  # Preselect whatever the marker says was installed last time.
  prev_selected=""
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    prev_selected+="${prev_selected:+, }$(label_for "$id")"
  done < <(marker_items)

  menu=()
  for entry in "${MENU_LAYOUT[@]}"; do
    menu+=("${entry%%|*}|$(label_for "${entry#*|}")")
  done

  menu_args=()
  [[ -n "$prev_selected" ]] && menu_args+=(--selected "$prev_selected")

  picks=""
  if picks="$(ui_choose_multi "What should I set up?" "${menu_args[@]}" --height 12 "${menu[@]}")"; then
    while IFS= read -r pick; do
      [[ -n "$pick" ]] || continue
      for entry in "${MENU_LAYOUT[@]}"; do
        id="${entry#*|}"
        # ui_choose_multi returns the label, not the section column
        if [[ "$pick" == "$(label_for "$id")" ]]; then
          selected+=("$id")
          break
        fi
      done
    done <<<"$picks"
  fi
fi

if ((${#selected[@]} == 0)); then
  printf '\nnothing selected — nothing to do.\n'
  exit 0
fi

# --- summary + confirm ------------------------------------------------------

summary=()
for id in "${selected[@]}"; do summary+=("$(name_for "$id")"); done
echo
ui_summary "Ready to install:" "${summary[@]}"
echo

if (( ! assume_yes )) && [[ "$mode" == wizard ]]; then
  ui_confirm "Install now?" || { printf '\nnothing installed.\n'; exit 0; }
  echo
fi

# --- run --------------------------------------------------------------------

total=${#selected[@]}
failed=()
done_ids=()
i=0
for id in "${selected[@]}"; do
  if step_cmd="$(cmd_for "$id")" && ui_step "$i" "$total" "$(name_for "$id")" -- bash -c "$step_cmd"; then
    done_ids+=("$id")
  else
    failed+=("$id")
    if is_fatal "$id"; then
      printf '\n✗ %s failed; stopping.\n' "$(name_for "$id")" >&2
      printf '  Fix it and re-run `ucli devmode` — nothing was recorded as installed.\n' >&2
      exit 1
    fi
    printf '  warning: %s failed; continuing\n' "$(name_for "$id")" >&2
  fi
  i=$(( i + 1 ))
done

# --- record -----------------------------------------------------------------

if ((${#done_ids[@]})); then
  # Merge with the previous run so "add more tools" keeps the earlier picks.
  merged=()
  while IFS= read -r id; do
    [[ -n "$id" ]] && merged+=("$id")
  done < <(marker_items)
  for id in "${done_ids[@]}"; do
    if ((${#merged[@]} == 0)) || ! contains "$id" "${merged[@]}"; then
      merged+=("$id")
    fi
  done

  write_marker "${merged[@]}"
  vs_commit devmode user "$DEVMODE_VERSION"
fi

echo
if ((${#failed[@]})); then
  ui_box "Developer Mode partially set up. Re-run 'ucli devmode' to retry: $(IFS=', '; printf '%s' "${failed[*]}")"
  exit 1
fi

ui_box "Developer Mode is on!  Re-run 'ucli devmode' any time to add more tools."
