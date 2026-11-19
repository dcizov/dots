#!/usr/bin/env bash
# debloat-desktop.sh: which installed packages are offered per desktop (never
# the desktop's own core), --list / --remove without the menu, and the
# snapshot only once something is actually being removed.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

debloat() { ( source ../private_dot_local/share/ucli/scripts/install/executable_debloat-desktop.sh "$@" ); }

# installed <pkg…> — pacman -Q answers for exactly these; -Qg gnome lists the
# gnome-group members among them.
installed() {
  t_minimal_path
  printf '%s\n' "$@" >"$T_ROOT/installed"
  stub pacman "case \$1 in
    -Q)  grep -qx \"\$2\" '$T_ROOT/installed' ;;
    -Qg) grep -E '^(gnome-shell|gdm|nautilus|baobab|epiphany|gnome-maps)\$' '$T_ROOT/installed' | sed 's/^/gnome /' ;;
    -Rs) exit 0 ;;
    *)   exit 1 ;;
  esac"
  t_config_file packages.bash <<'PKG'
GNOME_APP_OVERRIDES=(gnome-boxes)
GNOME_SYSTEM_EXTENSION_PACKAGES=(extension-manager)
DESKTOP_KDE_BASE=(plasma-desktop sddm kwin)
DESKTOP_KDE_ADDITIONS=(kate elisa)
DESKTOP_HYPRLAND_BASE=(hyprland waybar)
DESKTOP_HYPRLAND_ADDITIONS=(wofi)
PKG
}

test_gnome_offers_the_group_and_overrides_but_not_the_core() {
  installed gnome-shell gdm nautilus baobab epiphany gnome-boxes extension-manager
  t_run debloat gnome --list
  assert_status 0
  assert_eq $'baobab\nepiphany\ngnome-boxes\nextension-manager' "$T_OUT"
}

test_kde_never_offers_plasma_kwin_or_sddm() {
  installed plasma-desktop sddm kwin kate elisa
  t_run debloat kde --list
  assert_eq $'kate\nelisa' "$T_OUT"
}

test_hyprland_never_offers_hyprland_itself() {
  installed hyprland waybar wofi
  t_run debloat hyprland --list
  assert_eq $'waybar\nwofi' "$T_OUT"
}

test_the_desktop_is_detected_from_installed_packages() {
  installed plasma-desktop kate
  unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
  t_run debloat --list
  assert_status 0
  assert_eq "kate" "$T_OUT"
}

test_remove_takes_only_eligible_packages() {
  installed plasma-desktop sddm kwin kate elisa
  export UCLI_TEST_ROOT="$T_ROOT"
  t_run debloat kde --remove kate,elisa --no-snapshot
  assert_status 0
  assert_called "pacman -Rs --noconfirm kate elisa"
  t_run debloat kde --remove sddm
  assert_status 2
  assert_contains "$T_OUT" "not removable here: sddm"
  assert_not_called "pacman -Rs --noconfirm sddm"
}

test_removal_needs_root_but_listing_does_not() {
  ((EUID != 0)) || return 0
  installed hyprland waybar
  t_run debloat hyprland --list
  assert_status 0
  t_run debloat hyprland --remove waybar
  assert_status 1
  assert_contains "$T_OUT" "Removing packages needs root"
  assert_not_called "pacman -Rs"
}

test_without_a_terminal_the_menu_cancels_and_takes_no_snapshot() {
  installed hyprland waybar
  export UCLI_TEST_ROOT="$T_ROOT"
  t_run debloat hyprland </dev/null
  assert_status 0
  assert_contains "$T_OUT" "Cancelled."
  assert_not_called "pacman -Rs"
}

test_nothing_eligible_and_bad_arguments() {
  installed hyprland
  t_run debloat hyprland --list
  assert_contains "$T_OUT" "No debloatable hyprland packages found installed."
  t_run debloat xfce --list
  assert_status 2
  assert_contains "$T_OUT" "Invalid desktop: xfce"
  t_run debloat --bogus
  assert_status 2
  t_run debloat --help
  assert_status 0
  assert_contains "$T_OUT" "--remove a,b"
}

t_main
