#!/usr/bin/env bash
# install-paru.sh / install-shelly.sh and lib/aur.sh: a helper that is there is
# left alone, a repository package beats an AUR build, and the AUR build clones
# the package, imports paru's signing key for makepkg, and runs makepkg -si.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

paru_i()   { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-paru.sh "$@" ); }
shelly_i() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-shelly.sh "$@" ); }
aur_lib()  { source ../private_dot_local/share/ucli/scripts/lib/aur.sh; }

# toolchain [in-repo 0|1] — pacman (-Si answers per in-repo), sudo, a git that
# "clones" a PKGBUILD dir, gpg without the key, makepkg recording its cwd.
toolchain() {
  t_minimal_path
  stub sudo '"$@"'
  stub pacman "[[ \$1 == -Si ]] && exit $((1 - ${1:-0})); exit 0"
  stub git '[[ $1 == clone ]] && mkdir -p "${@: -1}"; exit 0'
  stub gpg '[[ $1 == --list-keys ]] && exit 2; exit 0'
  stub makepkg 'echo "makepkg in ${PWD##*/}: $*" >>"$T_CALLS"'
}

test_an_installed_helper_is_left_alone() {
  toolchain; stub paru; stub shelly
  t_run paru_i
  assert_contains "$T_OUT" "paru already installed"
  t_run shelly_i
  assert_contains "$T_OUT" "shelly already installed"
  assert_not_called "pacman"
}

test_a_repository_package_is_preferred() {
  toolchain 1
  t_run paru_i
  assert_status 0
  assert_called "pacman -S --needed --noconfirm paru"
  assert_not_called "git clone"
}

test_paru_is_built_from_the_aur_with_its_key_imported() {
  toolchain 0
  t_run paru_i --yes
  assert_status 0
  assert_called "pacman -S --needed --noconfirm git base-devel"
  assert_called "git clone -q https://aur.archlinux.org/paru.git"
  assert_called "gpg --recv-keys 48652EE482BF7507"
  assert_called "makepkg in paru: -si --noconfirm"
}

test_shelly_is_built_without_a_key() {
  toolchain 0
  t_run shelly_i
  assert_status 0
  assert_called "git clone -q https://aur.archlinux.org/shelly.git"
  assert_not_called "gpg --recv-keys"
  assert_called "makepkg in shelly: -si"
}

test_aur_build_keeps_stdout_clean_and_cleans_up() {
  toolchain 0
  aur_lib
  local out
  out="$(TMPDIR="$T_ROOT" aur_build paru 1 "" 2>/dev/null)"
  assert_eq "" "$out" "callers keep stdout for their one-line answer"
  [[ -z "$(find "$T_ROOT" -maxdepth 1 -name 'paru-build.*')" ]] || t_die "the build dir was left behind"
}

test_an_unimportable_key_warns_and_still_builds() {
  toolchain 0
  stub gpg 'exit 2'
  t_run paru_i
  assert_contains "$T_OUT" "could not import PGP key 48652EE482BF7507"
  assert_called "makepkg in paru"
}

test_no_pacman_and_bad_arguments() {
  t_minimal_path
  t_run paru_i
  assert_status 1
  assert_contains "$T_OUT" "pacman not found; cannot install paru"
  t_run shelly_i --bogus
  assert_status 2
}

t_main
