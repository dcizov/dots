#!/usr/bin/env bash
# install-aur-helper.sh: which AUR helper ucli uses — AUR_HELPER if set, else
# an installed shelly, else paru, else the distro default — printed as exactly
# one line on stdout, and installed (as the invoking user) when missing.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

helper() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-aur-helper.sh "$@" ); }

# distro <ID> — an os-release under UCLI_ETC_ROOT, and only the basics on PATH.
distro() {
  t_minimal_path
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
  printf 'ID=%s\n' "$1" >"$UCLI_ETC_ROOT/etc/os-release"
}

test_print_only_prefers_installed_shelly_then_paru() {
  distro arch; stub paru; stub shelly
  t_run helper --print-only
  assert_eq "shelly" "$T_OUT"
  rm "$T_BIN/shelly"
  t_run helper --print-only
  assert_eq "paru" "$T_OUT"
}

test_print_only_falls_back_to_the_distro_default() {
  distro arch
  t_run helper --print-only
  assert_eq "paru" "$T_OUT"
  distro cachyos
  t_run helper --print-only
  assert_eq "shelly" "$T_OUT"
}

test_a_configured_helper_wins_even_over_an_installed_one() {
  distro cachyos; stub shelly
  t_config_file packages.bash <<<'AUR_HELPER=""'
  t_config_file packages.local.bash <<<'AUR_HELPER="paru"'
  t_run helper --print-only
  assert_status 0
  assert_eq "paru" "$T_OUT"
}

test_an_unknown_configured_helper_is_an_error() {
  distro arch
  t_config_file packages.bash <<<'AUR_HELPER="yay"'
  t_run helper --print-only
  assert_status 2
  assert_contains "$T_OUT" "AUR_HELPER=yay is not a helper this script knows"
}

# deployed — the script with its deployed sibling names, so it can find
# install-paru.sh / install-shelly.sh; those are fakes that "install" a stub.
deployed() {
  D="$T_ROOT/scripts"
  mkdir -p "$D/install"
  ln -s "$(cd ../private_dot_local/share/ucli/scripts/lib && pwd)" "$D/lib"
  cp ../private_dot_local/share/ucli/scripts/install/executable_install-aur-helper.sh "$D/install/install-aur-helper.sh"
  local h
  for h in paru shelly; do
    printf '#!/usr/bin/env bash\necho "installing %s $*"\nprintf "#!/bin/sh\\n" >"%s/%s"; chmod +x "%s/%s"\necho "%s-installer $*" >>"$T_CALLS"\n' \
      "$h" "$T_BIN" "$h" "$T_BIN" "$h" "$h" >"$D/install/install-$h.sh"
  done
  chmod +x "$D"/install/*.sh
}

test_yes_installs_the_distro_default_and_prints_one_line() {
  distro arch; deployed
  t_run bash -c "'$D/install/install-aur-helper.sh' --yes 2>/dev/null"
  assert_status 0
  assert_eq "paru" "$T_OUT" "stdout carries the helper name and nothing else"
  assert_called "paru-installer --yes"
  assert_not_called "shelly-installer"
}

test_a_configured_helper_is_installed_without_asking() {
  distro arch; deployed
  t_config_file packages.bash <<<'AUR_HELPER="shelly"'
  t_run bash -c "'$D/install/install-aur-helper.sh' </dev/null 2>/dev/null"
  assert_status 0
  assert_eq "shelly" "$T_OUT"
  assert_called "shelly-installer"
}

test_an_installer_that_installs_nothing_is_caught() {
  distro arch; deployed
  printf '#!/usr/bin/env bash\necho "claims success"\n' >"$D/install/install-paru.sh"
  t_run bash -c "'$D/install/install-aur-helper.sh' --yes"
  assert_status 1
  assert_contains "$T_OUT" "no AUR helper on PATH after installing paru"
}

test_unasked_without_a_terminal_and_no_preference_stops() {
  distro arch; deployed
  t_run bash -c "'$D/install/install-aur-helper.sh' </dev/null"
  assert_status 2
  assert_not_called "installer"
}

test_arguments() {
  t_run helper --bogus
  assert_status 2
  t_run helper --help
  assert_contains "$T_OUT" "--print-only"
}

t_main
