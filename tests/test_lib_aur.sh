#!/usr/bin/env bash
# lib/aur.sh: the AUR lookups (RPC through python3, git ls-remote fallback),
# provider resolution, and aur_build (see test_install_aur_builds.sh).
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

aur() { source ../private_dot_local/share/ucli/scripts/lib/aur.sh; }

test_exists_asks_the_rpc_through_python() {
  aur
  stub python3 '[[ $2 == paru ]]'
  aur_exists paru || t_die "paru should exist"
  ! aur_exists nope-not-real || t_die "a missing package exists"
  assert_called "python3 - paru"
}

test_without_python_git_ls_remote_answers() {
  aur
  t_minimal_path
  stub git '[[ $2 == https://aur.archlinux.org/kwi-git.git ]]'
  aur_exists kwi-git || t_die "git fallback missed kwi-git"
  ! aur_exists nothing || t_die "git fallback invented a package"
}

test_without_python_or_git_nothing_exists() {
  aur
  t_minimal_path
  ! aur_exists paru || t_die "no way to ask, yet it answered yes"
}

test_provides_prints_the_provider() {
  aur
  stub python3 '[[ $2 == kwi ]] && echo kwi-git; exit 0'
  assert_eq "kwi-git" "$(aur_provides kwi)"
  assert_eq "" "$(aur_provides none)"
}

t_main
