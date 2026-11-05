#!/usr/bin/env bash
set -euo pipefail

# Curated GNOME defaults — what Bluefin bakes into the image with a gschema
# override, applied per user.
#
# Bluefin's `zz0-bluefin-modifications.gschema.override` does two things in one
# file: it sets `org.gnome.shell enabled-extensions` (the schema *default*, so
# every new user starts with them on) and it tunes the extensions and the shell —
# dock as a fixed bar with dots indicators, popup blur, center new windows, Super
# shortcuts, weekday in the clock, no hot corners. Those are defaults, not locks:
# dconf's user database wins over the schema default, so a user who changes
# something keeps it.
#
# This repo cannot use that mechanism honestly: an override lives in
# /usr/share/glib-2.0/schemas, which belongs to pacman, and glib-compile-schemas
# rewrites gschemas.compiled for the whole system. So the same values are applied
# as *user* settings instead, which for a single-user machine is the same result
# and is visible, inspectable and reversible (`dconf dump /org/gnome/`).
#
# "Default, not lock" is preserved by the rule below:
#
#   current == wanted        → already fine, nothing to do
#   current == schema default → you never touched it, so set it
#   anything else            → you chose something else: keep your value, say so
#                              (--force overrides that)
#
# The schema default is read with GSETTINGS_BACKEND=memory, i.e. gsettings with a
# backend that has no user values: whatever comes back is what the compiled schema
# ships. No python, no dconf path guessing.
#
# Keys whose schema is not installed are skipped and counted — dash-to-dock and
# blur-my-shell only exist once the extension is there, and the Nautilus terminal
# entry only once nautilus-open-any-terminal is.
#
# Usage: gnome-defaults.sh [--dry-run] [--force] [--status] [--no-restart]

dry_run=0
force=0
status_only=0
restart_nautilus=1
usage() {
  cat <<'USAGE'
usage: gnome-defaults.sh [--dry-run] [--force] [--status] [--no-restart]

Apply this repo's curated GNOME defaults (the values Bluefin ships in its gschema
override) to the current user's dconf.

  --dry-run     print what would change, write nothing
  --force       also overwrite keys you have set yourself
  --status      only report: value, wanted value, and why it differs
  --no-restart  do not restart Nautilus afterwards
USAGE
}
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    --force) force=1 ;;
    --status) status_only=1 ;;
    --no-restart) restart_nautilus=0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" 2>/dev/null | cut -d: -f6 || true)"
[[ -n "$real_home" ]] || real_home="${HOME:-}"

# Same helper as install-gnome-extension-set.sh: dconf and gsettings are per user,
# so from sudo they must run as the user with that user's HOME.
as_user() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
    runuser -u "$real_user" -- env -u XDG_CONFIG_HOME HOME="$real_home" \
      PATH="$real_home/.local/bin:$PATH" "$@"
  else
    "$@"
  fi
}

if ! command -v gsettings >/dev/null 2>&1; then
  echo "gsettings not found; is a desktop installed?" >&2
  exit 1
fi

# One line per setting: schema|key|value. The value is GVariant text exactly as
# `gsettings set` takes it — 'strings' quoted, lists in brackets, doubles bare.
# Commented sections are documentation; blank lines and # lines are ignored.
#
# Everything below is taken from Bluefin's zz0-bluefin-modifications.gschema.override
# (the file itself lives in projectbluefin/common), minus what is Bluefin's own
# identity (Adwaita Sans fonts, their wallpaper, Bazaar, their command menu) and
# plus the pieces this repo has instead (ghostty, the Nautilus extensions).
read -r -d '' SETTINGS <<'TABLE' || true
# ---------------------------------------------------------------- shell layout
# A fixed dock with maximised windows wants minimize/maximize back, and Alt-Tab
# switching windows while Super-Tab switches apps (Bluefin's pairing; GNOME's
# default maps both to apps).
org.gnome.desktop.wm.preferences|button-layout|':minimize,maximize,close'
org.gnome.desktop.wm.keybindings|show-desktop|['<Super>d']
org.gnome.desktop.wm.keybindings|switch-applications|['<Super>Tab']
org.gnome.desktop.wm.keybindings|switch-applications-backward|['<Shift><Super>Tab']
org.gnome.desktop.wm.keybindings|switch-windows|['<Alt>Tab']
org.gnome.desktop.wm.keybindings|switch-windows-backward|['<Shift><Alt>Tab']
org.gnome.desktop.wm.keybindings|unmaximize|['<Super>Down']
org.gnome.mutter|center-new-windows|true

# ---------------------------------------------------------------- look and feel
org.gnome.desktop.interface|enable-hot-corners|false
org.gnome.desktop.interface|clock-show-weekday|true
# GNOME 47+; skipped automatically on older shells.
org.gnome.desktop.interface|accent-color|'slate'
org.gnome.desktop.sound|allow-volume-above-100-percent|false
org.gnome.desktop.sound|theme-name|'freedesktop'
org.gnome.desktop.peripherals.keyboard|numlock-state|true
# Not Bluefin's: this repo's. The power button asks (dock, restart, power off)
# instead of suspending on a desktop that may not resume, and file choosers sort
# folders first in GTK3 and GTK4 apps alike.
org.gnome.settings-daemon.plugins.power|power-button-action|'interactive'
org.gtk.Settings.FileChooser|sort-directories-first|true
org.gtk.gtk4.Settings.FileChooser|sort-directories-first|true

# The dock contents. Bluefin's list is firefox, thunderbird, nautilus, bazaar,
# software, code; this repo ships firefox + ghostty and no app store.
org.gnome.shell|favorite-apps|['org.mozilla.firefox.desktop', 'com.mitchellh.ghostty.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop', 'org.gnome.TextEditor.desktop']

# ---------------------------------------------------------------- dash-to-dock
# A calm, always-visible bar: 80% dark background, dots instead of squares, no
# overview on startup, straight corners off so it follows the shell's rounding.
org.gnome.shell.extensions.dash-to-dock|dock-fixed|true
org.gnome.shell.extensions.dash-to-dock|disable-overview-on-startup|true
org.gnome.shell.extensions.dash-to-dock|force-straight-corner|false
org.gnome.shell.extensions.dash-to-dock|running-indicator-style|'DOTS'
org.gnome.shell.extensions.dash-to-dock|animation-time|0.15
# One steady 80 % dark bar: FIXED ignores the alpha pair unless customize-alphas is
# on, and both are set to the same value so it stays 80 % opaque instead of turning
# solid when a window is maximised (which is what DYNAMIC does).
org.gnome.shell.extensions.dash-to-dock|transparency-mode|'FIXED'
org.gnome.shell.extensions.dash-to-dock|customize-alphas|true
org.gnome.shell.extensions.dash-to-dock|min-alpha|0.8
org.gnome.shell.extensions.dash-to-dock|max-alpha|0.8
org.gnome.shell.extensions.dash-to-dock|custom-background-color|true
org.gnome.shell.extensions.dash-to-dock|background-color|'rgb(40,40,40)'

# ---------------------------------------------------------------- blur-my-shell
org.gnome.shell.extensions.blur-my-shell.dash-to-dock|blur|true
org.gnome.shell.extensions.blur-my-shell.popup|blur|true

# ---------------------------------------------------------------- Nautilus
# "Open in terminal" only appears once a terminal it knows is named; ghostty is
# the terminal this repo installs (DESKTOP_TERMINAL_GNOME). keybindings stays
# empty — the entry is in the context menu, no accelerator stealing Ctrl+Alt+T.
# flatpak=none means "run the host binary", not "wrap it in flatpak run".
com.github.stunkymonkey.nautilus-open-any-terminal|terminal|'ghostty'
com.github.stunkymonkey.nautilus-open-any-terminal|keybindings|''
com.github.stunkymonkey.nautilus-open-any-terminal|new-tab|false
com.github.stunkymonkey.nautilus-open-any-terminal|flatpak|'none'
TABLE

set_count=0
ok_count=0
kept_count=0
skipped_count=0
failed=0
status_lines=()

# One `gsettings list-schemas` for the whole table, and one `list-keys` per schema
# (they are cheap, but forty keys times two forks is not).
schemas_list="$(as_user gsettings list-schemas 2>/dev/null || true)"
declare -A keys_of=()

# Values are compared as gsettings prints them ("true", "'slate'", "['a', 'b']").
apply_one() {
  local schema="$1" key="$2" wanted="$3"

  if ! grep -qx "$schema" <<<"$schemas_list"; then
    skipped_count=$((skipped_count + 1))
    status_lines+=("  skip    $schema $key — schema not installed")
    return 0
  fi
  if [[ -z "${keys_of[$schema]:-}" ]]; then
    keys_of[$schema]="$(as_user gsettings list-keys "$schema" 2>/dev/null || true)"
  fi
  if ! grep -qx "$key" <<<"${keys_of[$schema]}"; then
    skipped_count=$((skipped_count + 1))
    status_lines+=("  skip    $schema $key — key not in this version")
    return 0
  fi

  local current schema_default
  current="$(as_user gsettings get "$schema" "$key" 2>/dev/null || true)"
  schema_default="$(GSETTINGS_BACKEND=memory gsettings get "$schema" "$key" 2>/dev/null || true)"

  if [[ "$current" == "$wanted" ]]; then
    ok_count=$((ok_count + 1))
    if (( status_only )); then
      status_lines+=("  ok      $schema $key = $wanted")
    fi
    return 0
  fi

  if [[ "$current" != "$schema_default" ]] && (( ! force )); then
    kept_count=$((kept_count + 1))
    status_lines+=("  keep    $schema $key = $current (yours, not the repo's $wanted)")
    return 0
  fi

  if (( status_only )); then
    status_lines+=("  set     $schema $key: $current -> $wanted")
    return 0
  fi
  if (( dry_run )); then
    echo "+ gsettings set $schema $key $wanted"
    set_count=$((set_count + 1))
    return 0
  fi

  if ! as_user gsettings set "$schema" "$key" "$wanted" 2>/dev/null; then
    echo "warning: could not set $schema $key to $wanted" >&2
    failed=1
    return 0
  fi
  local after
  after="$(as_user gsettings get "$schema" "$key" 2>/dev/null || true)"
  if [[ "$after" != "$wanted" ]]; then
    echo "warning: $schema $key is $after after setting it to $wanted" >&2
    failed=1
    return 0
  fi
  set_count=$((set_count + 1))
  return 0
}

while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  schema="${line%%|*}"
  rest="${line#*|}"
  key="${rest%%|*}"
  value="${rest#*|}"
  apply_one "$schema" "$key" "$value"
done <<<"$SETTINGS"

if (( status_only )); then
  ((${#status_lines[@]})) && printf '%s\n' "${status_lines[@]}"
  printf 'gnome defaults: %d already correct, %d yours (kept), %d not applicable\n' \
    "$ok_count" "$kept_count" "$skipped_count"
  exit 0
fi

if (( dry_run )); then
  printf 'gnome defaults: %d to set, %d already correct, %d yours (kept), %d not applicable\n' \
    "$set_count" "$ok_count" "$kept_count" "$skipped_count"
  exit "$failed"
fi

# Nautilus reads its extensions at start, so a machine that already had it open
# would show none of the new context-menu entries until it is restarted. -q quits
# the file manager without touching the rest of the session; the next window
# reopens with the extensions loaded.
if (( restart_nautilus )) && command -v nautilus >/dev/null 2>&1; then
  if pgrep -u "$real_user" -x nautilus >/dev/null 2>&1; then
    if as_user nautilus -q >/dev/null 2>&1; then
      echo "nautilus restarted (extensions load on start)"
    else
      echo "note: could not restart Nautilus; run 'nautilus -q' yourself" >&2
    fi
  fi
fi

if (( ${#status_lines[@]} )); then
  printf '%s\n' "${status_lines[@]}"
fi
printf 'gnome defaults: %d set, %d already correct, %d yours (kept), %d not applicable\n' \
  "$set_count" "$ok_count" "$kept_count" "$skipped_count"
if (( failed )); then
  echo "warning: some settings could not be applied (see above)" >&2
fi
exit "$failed"
