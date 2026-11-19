#!/usr/bin/env bash
# install-overrides.sh (`ucli apps`): the order of the steps it delegates to,
# which failures are fatal and which only warn, and the GNOME-only tail.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

apps() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-overrides.sh "$@" ); }

STEPS=(install-packages install-flatpaks install-flatpak-gtk-theme install-firefox-profile
  install-firefox-policies install-gnome-extension-set gnome-defaults)

siblings() {
  S="$(t_deployed install/install-overrides)"
  local s
  for s in "${STEPS[@]}"; do t_fake_script "${S%/*}/$s.sh"; done
  stub sudo '"$@"'
}
order() { awk '{print $1}' "$T_CALLS" | grep -v '^sudo$' | tr '\n' ' '; }

test_everything_runs_in_order_on_gnome() {
  siblings
  XDG_CURRENT_DESKTOP=GNOME t_run bash "$S" --force
  assert_status 0
  assert_eq "install-packages.sh install-flatpaks.sh install-flatpak-gtk-theme.sh install-firefox-profile.sh install-firefox-policies.sh install-gnome-extension-set.sh gnome-defaults.sh " "$(order)"
  assert_called "install-packages.sh apps"
  assert_called "install-firefox-profile.sh --force"
  assert_called "install-gnome-extension-set.sh personal --force"
  assert_called "sudo ${S%/*}/install-firefox-policies.sh"
  assert_not_called "gnome-defaults.sh --force"
}

test_other_desktops_skip_the_gnome_tail() {
  siblings
  XDG_CURRENT_DESKTOP=KDE t_run bash "$S"
  assert_status 0
  assert_not_called "install-gnome-extension-set.sh"
  assert_not_called "gnome-defaults.sh"
}

test_system_scope_reaches_the_flatpak_theme() {
  siblings
  t_run bash "$S" --system
  assert_called "install-flatpak-gtk-theme.sh --system"
}

test_package_failures_stop_but_cosmetic_ones_only_warn() {
  siblings
  t_fake_script "${S%/*}/install-flatpak-gtk-theme.sh" 'exit 1'
  t_fake_script "${S%/*}/install-firefox-policies.sh" 'exit 3'
  t_run bash "$S"
  assert_status 0
  assert_contains "$T_OUT" "Flatpak GTK theme extension not installed"
  assert_contains "$T_OUT" "Firefox extensions were not configured (exit 3)"
  t_fake_script "${S%/*}/install-packages.sh" 'exit 1'
  : >"$T_CALLS"
  t_run bash "$S"
  assert_status 1
  assert_not_called "install-flatpaks.sh"
}

test_arguments() {
  t_run apps --bogus
  assert_status 2
  t_run apps --help
  assert_contains "$T_OUT" "Usage: install-overrides.sh [--force] [--system]"
}

t_main
