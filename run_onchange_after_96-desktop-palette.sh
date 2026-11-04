#!/bin/sh
# Point the GNOME background at the palette.
#
# Runs whenever this file changes. Silent no-op when there is no GNOME
# session (no gsettings, or no session bus), so it is harmless on the dev
# box and on any non-GNOME desktop.
#
# Only the background is touched. The desktop's colour scheme and accent
# colour are left exactly as they are — repainting every GTK app is not a
# side effect of aligning a background.

command -v gsettings >/dev/null 2>&1 || exit 0
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || exit 0

set_key() {  # <schema> <key> <value>
  gsettings set "$1" "$2" "$3" 2>/dev/null || true
}

# The repo ships no background images, so only the solid palette colour is set:
# pointing at a file that is not there would leave GNOME with a broken picture.
set_key org.gnome.desktop.background color-shading-type 'solid'
set_key org.gnome.desktop.background primary-color      '#1c1c1f'
set_key org.gnome.desktop.background secondary-color    '#1c1c1f'

exit 0
