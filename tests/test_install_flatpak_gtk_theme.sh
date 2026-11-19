#!/usr/bin/env bash
# install-flatpak-gtk-theme.sh: the adw-gtk3 runtime extensions from Flathub,
# installed only when missing and verified afterwards. flatpak is a stateful
# fake: `list` prints what `install` has put in a file.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

theme() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-flatpak-gtk-theme.sh "$@" ); }

# fake_flatpak [installs 0|1] — with 0, install "succeeds" without installing.
fake_flatpak() {
  export UCLI_TEST_ROOT="$T_ROOT/root" FP="$T_ROOT/flatpak-installed"
  : >"$FP"
  stub flatpak "case \$1 in
    remotes) echo flathub ;;
    list)    cat \"\$FP\" ;;
    install) [[ ${1:-1} == 1 ]] && for a in \"\${@:5}\"; do echo \"\$a\" >>\"\$FP\"; done; exit 0 ;;
    remote-add) exit 0 ;;
  esac"
}
host_theme() { mkdir -p "$UCLI_TEST_ROOT/usr/share/themes/adw-gtk3-dark"; }

test_missing_extensions_are_installed_and_verified() {
  fake_flatpak; host_theme
  t_run theme
  assert_status 0
  assert_called "flatpak install --user -y flathub org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark"
  assert_contains "$T_OUT" "2/2 adw-gtk3 extension(s) installed (--user)"
  assert_contains "$T_OUT" "host theme: adw-gtk3-dark"
}

test_installed_extensions_are_not_reinstalled() {
  fake_flatpak; host_theme
  printf 'org.gtk.Gtk3theme.adw-gtk3\norg.gtk.Gtk3theme.adw-gtk3-dark\n' >"$FP"
  t_run theme
  assert_status 0
  assert_contains "$T_OUT" "org.gtk.Gtk3theme.adw-gtk3: already installed"
  assert_not_called "flatpak install"
}

test_a_success_that_installed_nothing_is_a_failure() {
  fake_flatpak 0; host_theme
  t_run theme
  assert_status 1
  assert_contains "$T_OUT" "flatpak reported success, but only 0/2 extension(s) are installed"
}

test_a_missing_flathub_remote_is_added() {
  fake_flatpak; host_theme
  stub flatpak "case \$1 in remotes) ;; list) ;; remote-add) echo added >/dev/null ;; install) exit 1 ;; esac; exit 0"
  t_run theme
  assert_called "flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
}

test_no_host_theme_warns() {
  fake_flatpak
  t_run theme --dry-run
  assert_contains "$T_OUT" "adw-gtk3 is not installed on the host"
  assert_contains "$T_OUT" "+ flatpak install --user -y flathub"
  assert_not_called "flatpak install"
}

test_system_scope_needs_root() {
  ((EUID != 0)) || return 0
  fake_flatpak; host_theme
  t_run theme --system
  assert_status 1
  assert_contains "$T_OUT" "--system needs root"
}

test_without_flatpak_there_is_nothing_to_do() {
  t_minimal_path
  t_run theme
  assert_status 0
  assert_contains "$T_OUT" "flatpak is not installed"
  t_run theme --bogus
  assert_status 2
}

t_main
