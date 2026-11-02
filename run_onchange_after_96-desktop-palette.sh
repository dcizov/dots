#!/bin/sh
# Point GNOME at the same palette as the terminals and the prompt.
#
# Runs whenever this file changes. Silent no-op when there is no GNOME
# session (no gsettings, or no session bus), so it is harmless on the dev
# box and on any non-GNOME desktop.

command -v gsettings >/dev/null 2>&1 || exit 0
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || exit 0

solid="${HOME}/.local/share/backgrounds/lambda.xml"
png="${HOME}/.local/share/backgrounds/lambda.png"
set_key() {  # <schema> <key> <value>
  gsettings set "$1" "$2" "$3" 2>/dev/null || true
}

# The XML is a single flat colour: no scaling and no resampling, so it stays
# pixel-identical to the terminal background on every resolution and hidpi
# factor. Swap in the PNG below if you would rather have the soft glow.
picture="file://${solid}"
[ -f "$solid" ] || picture="file://${png}"

set_key org.gnome.desktop.background picture-uri       "$picture"
set_key org.gnome.desktop.background picture-uri-dark  "$picture"
set_key org.gnome.desktop.background color-shading-type 'solid'
set_key org.gnome.desktop.background primary-color      '#222e34'
set_key org.gnome.desktop.background secondary-color    '#222e34'
set_key org.gnome.desktop.screensaver picture-uri       "$picture"

# Keep the shell chrome dark so it sits on that background instead of glowing.
set_key org.gnome.desktop.interface color-scheme 'prefer-dark'

# GNOME 47+ has an accent colour. libadwaita paints buttons, selection and
# focus rings with it, so this is the one lever that makes GTK apps match.
if gsettings list-keys org.gnome.desktop.interface 2>/dev/null | grep -qx 'accent-color'; then
  for c in teal slate purple; do
    if gsettings range org.gnome.desktop.interface accent-color 2>/dev/null | grep -q "'$c'"; then
      set_key org.gnome.desktop.interface accent-color "$c"
      break
    fi
  done
fi

exit 0
