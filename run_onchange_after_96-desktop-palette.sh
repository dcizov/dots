#!/bin/sh
# Point the GNOME background at the palette.
#
# Runs whenever this file changes. Plasma can have both gsettings and a
# session bus, so require a GNOME session rather than just those tools.
#
# Only the background is touched. The desktop's colour scheme and accent
# colour are left exactly as they are — repainting every GTK app is not a
# side effect of aligning a background.

case ":${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}:" in
  *:[Gg][Nn][Oo][Mm][Ee]:*|*:[Gg][Nn][Oo][Mm][Ee]-[Cc]lassic:*) ;;
  *) exit 0 ;;
esac
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
