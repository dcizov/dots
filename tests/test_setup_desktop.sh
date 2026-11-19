#!/usr/bin/env bash
# setup-desktop.sh: which desktop (argument, chezmoi data, session, installed
# packages), its packages in one pacman transaction minus the removal list,
# the removal of what an installer put there anyway, the session service, and
# the hand-offs to the shell, extension, Firefox and snapshot steps.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

desktop_setup() { ( source ../private_dot_local/share/ucli/scripts/install/executable_setup-desktop.sh "$@" ); }

SIBLINGS=(install-aur-helper install-packages install-shell install-gnome-extension-set gnome-defaults
  install-flatpak-gtk-theme install-firefox-profile install-gnome-extensions-cli)

# machine <installed…> — the deployed script with recording siblings, a pacman
# whose repos hold repo-* and whose -Q/-Rns use a file, runuser/sudo pass-through.
machine() {
  export UCLI_TEST_ROOT="$T_ROOT/root" USER=alice INST="$T_ROOT/installed"
  printf '%s\n' "$@" >"$INST"
  S="$(t_deployed install/setup-desktop)"
  local s
  for s in "${SIBLINGS[@]}"; do t_fake_script "${S%/*}/$s.sh"; done
  t_fake_script "${S%/*}/install-aur-helper.sh" 'echo paru'
  t_fake_script "${S%/*}/../system/snapshot-fresh-install.sh"
  stub sudo '"$@"'
  stub runuser 'while [[ $1 != -- ]]; do shift; done; shift; [[ $1 == env ]] && shift; while [[ $1 == *=* ]]; do shift; done; "$@"'
  stub systemctl
  stub paru
  stub pacman 'case $1 in
    -Si) [[ $2 == repo-* ]] ;;
    -Sgq) exit 1 ;;
    -Q)  grep -qx "$2" "$INST" ;;
    -Rns) shift 2; for p in "$@"; do grep -vx "$p" "$INST" >"$INST.n"; mv "$INST.n" "$INST"; done ;;
    *) exit 0 ;;
  esac'
  t_config_file packages.bash <<'PKG'
DESKTOP_GNOME_BASE=(repo-gnome-shell repo-nautilus)
DESKTOP_GNOME_ADDITIONS=(repo-gnome-tweaks)
SERVICES_GNOME=(repo-gdm)
DESKTOP_REMOVE_GNOME=(repo-epiphany repo-yelp)
DESKTOP_KDE_BASE=(repo-plasma)
DESKTOP_KDE_ADDITIONS=()
SERVICES_KDE=(repo-sddm)
DESKTOP_REMOVE_KDE=()
DESKTOP_HYPRLAND_BASE=(repo-hyprland)
DESKTOP_HYPRLAND_ADDITIONS=(aur-hyprshot)
SERVICES_HYPRLAND=(repo-sddm)
DESKTOP_REMOVE_HYPRLAND=()
PKG
}

test_gnome_installs_in_one_transaction_and_hands_off_every_step() {
  machine repo-epiphany
  t_run bash "$S" gnome
  assert_status 0
  assert_called "pacman -S --needed --noconfirm --ignore=repo-epiphany,repo-yelp repo-gnome-shell repo-nautilus repo-gnome-tweaks repo-gdm"
  assert_eq 1 "$(grep -c '^pacman -S ' "$T_CALLS")" "one install transaction"
  assert_called "snapshot-fresh-install.sh before removing gnome group packages"
  assert_called "pacman -Rns --noconfirm repo-epiphany"
  assert_called "systemctl enable repo-gdm.service"
  assert_called "install-shell.sh"
  assert_called "install-gnome-extension-set.sh managed"
  assert_called "install-gnome-extension-set.sh personal"
  assert_called "gnome-defaults.sh"
  assert_called "install-firefox-profile.sh"
  assert_called "snapshot-fresh-install.sh gnome Setup"
}

test_aur_members_go_to_the_helper() {
  machine
  t_run bash "$S" hyprland --no-snapshot
  assert_status 0
  assert_called "pacman -S --needed --noconfirm repo-hyprland repo-sddm"
  assert_called "paru -S --needed aur-hyprshot"
  assert_called "snapshot-fresh-install.sh --no-snapshot hyprland Setup"
  assert_not_called "install-gnome-extension-set.sh"
}

test_plasma_from_chezmoi_data_means_kde() {
  machine
  stub chezmoi 'echo "{\"desktop\": \"plasma\"}"'
  t_run bash "$S"
  assert_status 0
  assert_called "pacman -S --needed --noconfirm repo-plasma repo-sddm"
}

test_the_session_and_then_installed_packages_pick_the_desktop() {
  machine repo-hyprland
  XDG_CURRENT_DESKTOP=GNOME t_run bash "$S"
  assert_called "repo-gnome-shell"
  : >"$T_CALLS"
  stub pacman 'case $1 in -Si) [[ $2 == repo-* ]] ;; -Sgq) exit 1 ;; -Q) [[ $2 == hyprland ]] ;; *) exit 0 ;; esac'
  t_run bash "$S"
  assert_called "pacman -S --needed --noconfirm repo-hyprland repo-sddm"
}

test_nothing_to_remove_takes_no_snapshot() {
  machine
  t_run bash "$S" gnome
  assert_contains "$T_OUT" "nothing to remove from the gnome group"
  assert_not_called "before removing gnome group packages"
}

test_arguments_and_root() {
  t_run desktop_setup --bogus
  assert_status 2
  t_run desktop_setup --help
  assert_contains "$T_OUT" "setup-desktop"
  ((EUID != 0)) || return 0
  t_run desktop_setup gnome
  assert_status 1
  assert_contains "$T_OUT" "Run as root: sudo ucli setup-desktop"
  export UCLI_TEST_ROOT="$T_ROOT"
  t_run desktop_setup xfce
  assert_status 2
  assert_contains "$T_OUT" "Invalid desktop: xfce"
}

t_main
