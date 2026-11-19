#!/usr/bin/env bash
# install-flatpaks.sh: which Flatpaks each mode selects for this desktop, role
# and gaming flag (from chezmoi data), and the flathub + install calls.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

flatpaks() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-flatpaks.sh "$@" ); }

# machine <role> <gaming> — chezmoi data says so; packages.bash has one app per
# array so the selection is visible.
machine() {
  stub chezmoi "echo '{\"role\": \"$1\", \"gaming\": $2, \"desktop\": \"auto\"}'"
  stub flatpak
  t_config_file packages.bash <<'PKG'
APP_FLATPAKS=(org.app.One)
GNOME_FLATPAKS=(org.gnome.Extra)
KDE_FLATPAKS=(org.kde.Extra)
HYPRLAND_FLATPAKS=()
DEV_FLATPAKS=(io.podman_desktop.PodmanDesktop)
GAMING_FLATPAKS=(com.valvesoftware.Steam)
PERSONAL_FLATPAKS=()
PKG
}

test_apps_take_the_desktop_set_and_the_personal_overlay() {
  machine dev false
  t_config_file packages.local.bash <<<'PERSONAL_FLATPAKS=(com.spotify.Client org.app.One)'
  t_run flatpaks --desktop=gnome apps
  assert_status 0
  assert_contains "$T_OUT" "flatpak apps: org.app.One com.spotify.Client org.gnome.Extra"
  assert_called "flatpak remote-add --user --if-not-exists flathub"
  assert_called "flatpak install --user -y flathub org.app.One com.spotify.Client org.gnome.Extra"
}

test_dev_and_gaming_follow_the_role() {
  machine dev false
  t_run flatpaks --dry-run dev
  assert_contains "$T_OUT" "flatpak apps: io.podman_desktop.PodmanDesktop"
  t_run flatpaks --dry-run gaming
  assert_contains "$T_OUT" "flatpak apps: (none)"
  machine minimal true
  t_run flatpaks --dry-run gaming
  assert_contains "$T_OUT" "flatpak apps: com.valvesoftware.Steam"
}

test_a_mode_that_selects_nothing_succeeds_quietly() {
  # dev on a non-dev role used to end the script with exit 1 and no message
  machine minimal false
  t_run flatpaks dev
  assert_status 0
  assert_contains "$T_OUT" "flatpak apps: (none)"
  assert_not_called "flatpak install"
  t_run flatpaks --desktop=kde full
  assert_status 0
  assert_contains "$T_OUT" "flatpak apps: org.app.One org.kde.Extra"
}

test_base_installs_nothing_but_succeeds() {
  machine dev true
  t_run flatpaks base
  assert_status 0
  assert_not_called "flatpak install"
}

test_system_scope_goes_through_sudo_for_the_remote() {
  machine dev false
  stub sudo '"$@"'
  t_run flatpaks --system --desktop=none apps
  assert_called "sudo flatpak remote-add --system --if-not-exists flathub"
  assert_called "flatpak install --system -y flathub org.app.One"
}

test_bad_arguments() {
  machine dev false
  t_run flatpaks
  assert_status 2
  t_run flatpaks sideways
  assert_status 2
  assert_contains "$T_OUT" "unknown mode: sideways"
  t_run flatpaks --desktop=cosmic apps
  assert_status 1
  assert_contains "$T_OUT" "Unsupported desktop: cosmic"
}

t_main
