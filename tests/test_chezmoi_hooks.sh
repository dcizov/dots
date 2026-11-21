#!/usr/bin/env bash
# The run_onchange_ hooks chezmoi runs after an apply: the GNOME background
# (only in a GNOME session with a bus, never Plasma) and the bat theme cache.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

palette() { ( source ../run_onchange_after_96-desktop-palette.sh ); }
# The bat hook is a template for its theme hash; its one template line is a
# comment, so dropping it gives the script chezmoi runs.
bat_hook() { sed '/{{/d' ../run_onchange_after_97-bat-theme.sh.tmpl | sh; }

test_gnome_gets_the_solid_palette_background() {
  stub gsettings
  XDG_CURRENT_DESKTOP=ubuntu:GNOME DBUS_SESSION_BUS_ADDRESS=unix:path=/x t_run palette
  assert_status 0
  assert_called "gsettings set org.gnome.desktop.background color-shading-type solid"
  assert_called "gsettings set org.gnome.desktop.background primary-color #1c1c1f"
}

test_plasma_and_bus_less_sessions_are_left_alone() {
  stub gsettings
  XDG_CURRENT_DESKTOP=KDE DBUS_SESSION_BUS_ADDRESS=unix:path=/x t_run palette
  XDG_CURRENT_DESKTOP=GNOME t_run palette
  assert_status 0
  assert_not_called "gsettings"
}

test_bat_rebuilds_its_cache_only_when_installed() {
  stub bat
  t_run bat_hook
  assert_status 0
  assert_called "bat cache --build"
  rm "$T_BIN/bat"; t_minimal_path
  t_run bat_hook
  assert_status 0
}

test_the_bat_hook_tracks_the_theme_file() {
  grep -q 'include "private_dot_config/bat/themes/Lambda.tmTheme" | sha256sum' ../run_onchange_after_97-bat-theme.sh.tmpl \
    || t_die "the hook no longer hashes the theme: editing it would not rebuild the cache"
  [[ -f ../private_dot_config/bat/themes/Lambda.tmTheme ]] || t_die "the hashed theme file is gone"
}

t_main
