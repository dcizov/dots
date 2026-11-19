#!/usr/bin/env bash
# tweaks.sh (`ucli tweak`): the TWEAKS registry (packages.bash, overridable in
# the overlay) — list, status, enable (installing a missing repo package
# first), disable (keeping the package). systemctl is a stateful fake.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

tweak() { ( source ../private_dot_local/share/ucli/scripts/system/executable_tweaks.sh "$@" ); }

registry() {
  export USER=alice SD="$T_ROOT/sd"
  mkdir -p "$SD"
  t_config_file packages.bash <<'PKG'
TWEAKS=(
  "bluetooth|bluetooth.service|bluez|system|Bluetooth"
  "syncthing|syncthing@.service|syncthing|template|Syncthing for you"
  "printing|cups.service|cups|system|Printing"
)
PKG
  stub sudo '"$@"'
  stub pacman 'case $1 in -Q) [[ $2 == bluez || $2 == syncthing ]] ;; -Si) [[ $2 != nosuch ]] ;; *) exit 0 ;; esac'
  stub systemctl 'f="$SD/${@: -1}"; case $1 in
    is-enabled) [[ -e $f.enabled ]] ;; is-active) [[ -e $f.active ]] ;;
    enable) : >"$SD/$3.enabled"; : >"$SD/$3.active" ;;
    disable) rm -f "$SD/$3.enabled" "$SD/$3.active" ;;
  esac'
}

test_enable_and_disable_a_system_service() {
  registry
  t_run tweak enable bluetooth
  assert_status 0
  assert_called "systemctl enable --now bluetooth.service"
  t_run tweak enable bluetooth
  assert_contains "$T_OUT" "already enabled and running"
  t_run tweak disable bluetooth
  assert_called "systemctl disable --now bluetooth.service"
  assert_contains "$T_OUT" "the bluez package stays installed"
  t_run tweak disable bluetooth
  assert_contains "$T_OUT" "already off"
}

test_template_units_are_the_users_instance() {
  registry
  t_run tweak enable syncthing
  assert_called "systemctl enable --now syncthing@alice.service"
}

test_a_missing_package_is_installed_first_unless_told_not_to() {
  registry
  t_run tweak enable printing --no-install
  assert_status 1
  assert_contains "$T_OUT" "package cups is not installed and --no-install was given"
  t_run tweak enable printing
  assert_called "pacman -S --needed --noconfirm cups"
  assert_called "systemctl enable --now cups.service"
}

test_the_overlay_can_override_the_registry() {
  registry
  t_config_file packages.local.bash <<<'TWEAKS=("ssh|sshd.service|openssh|system|Remote login")'
  t_run tweak list
  assert_contains "$T_OUT" "ssh"
  assert_not_contains "$T_OUT" "bluetooth"
}

test_list_status_and_dry_run() {
  registry
  t_run tweak list
  assert_contains "$T_OUT" "cups (not installed)"
  assert_contains "$T_OUT" "bluez ✓"
  t_run tweak status syncthing
  assert_contains "$T_OUT" "unit:    syncthing@alice.service"
  assert_contains "$T_OUT" "enabled: no"
  t_run tweak enable printing --dry-run
  assert_contains "$T_OUT" "+ sudo pacman -S --needed --noconfirm cups"
  assert_contains "$T_OUT" "+ sudo systemctl enable --now cups.service"
  assert_not_called "systemctl enable"
}

test_errors() {
  registry
  t_run tweak enable nosuch
  assert_status 2
  assert_contains "$T_OUT" "no such tweak: nosuch"
  t_run tweak enable
  assert_status 2
  t_run tweak frobnicate x
  assert_status 2
  rm "$HOME/.config/ucli/packages.bash"
  t_run tweak list
  assert_status 1
  assert_contains "$T_OUT" "no package registry"
}

t_main
