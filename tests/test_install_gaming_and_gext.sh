#!/usr/bin/env bash
# install-gaming-profile.sh: packages + Flatpaks for gaming, skipped on
# CachyOS. install-gnome-extensions-cli.sh: gext through pipx, found on PATH
# afterwards even when ~/.local/bin was not on it yet.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

gaming() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-gaming-profile.sh "$@" ); }
gext_cli() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-gnome-extensions-cli.sh "$@" ); }

os() {
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
  printf 'ID=%s\n' "$1" >"$UCLI_ETC_ROOT/etc/os-release"
}

test_gaming_installs_packages_then_flatpaks() {
  t_minimal_path; os arch
  S="$(t_deployed install/install-gaming-profile)"
  t_fake_script "${S%/*}/install-packages.sh"
  t_fake_script "${S%/*}/install-flatpaks.sh"
  t_run bash "$S"
  assert_status 0
  assert_called "install-packages.sh --force gaming"
  assert_called "install-flatpaks.sh gaming"
}

test_gaming_is_left_to_cachyos_hello_on_cachyos() {
  t_minimal_path; os cachyos
  t_run gaming
  assert_status 0
  assert_contains "$T_OUT" "CachyOS detected"
  assert_not_called "install-packages"
}

test_gext_lands_on_path_even_from_a_fresh_login() {
  t_minimal_path
  # pipx lives in /usr/bin like Arch's python-pipx, and puts gext in ~/.local/bin
  stub pipx 'mkdir -p "$HOME/.local/bin"; printf "#!/bin/sh\necho gext 0.10\n" >"$HOME/.local/bin/gext"; chmod +x "$HOME/.local/bin/gext"'
  t_run gext_cli
  assert_status 0
  assert_called "pipx install gnome-extensions-cli"
  assert_contains "$T_OUT" "gnome-extensions-cli (gext) installed successfully"
  assert_contains "$T_OUT" "gext 0.10"
}

test_gext_already_installed_and_missing_pipx() {
  t_minimal_path
  t_run gext_cli
  assert_status 1
  assert_contains "$T_OUT" "pipx not found; install it first"
  stub pipx; stub gext
  t_run gext_cli
  assert_status 0
  assert_contains "$T_OUT" "already installed"
  assert_not_called "pipx install"
}

test_a_pipx_install_that_yields_no_gext_fails() {
  t_minimal_path
  stub pipx
  t_run gext_cli
  assert_status 1
  assert_contains "$T_OUT" "gext not found on PATH after install"
}

t_main
