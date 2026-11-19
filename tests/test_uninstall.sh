#!/usr/bin/env bash
# uninstall.sh: removes what ucli deployed and installed — and never the
# dotfiles repository (it can hold unpushed commits) or the personal files in
# ~/.config/ucli that the repo does not manage.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

uninstall() { ( source ../private_dot_local/share/ucli/scripts/install/executable_uninstall.sh "$@" ); }

deployed_home() {
  mkdir -p "$HOME/.config/ucli/firefox" "$HOME/.config/ucli/recipes" "$HOME/.config/zsh/conf.d" \
    "$HOME/.local/bin" "$HOME/.local/share/chezmoi/.git" "$HOME/.oh-my-zsh" "$HOME/.config/chezmoi" "$HOME/Documents"
  : >"$HOME/.zshrc"; : >"$HOME/.local/bin/ucli"; : >"$HOME/.config/ucli/justfile"
  : >"$HOME/.config/ucli/recipes/system.just"; : >"$HOME/.config/ucli/firefox/user.js"
  echo 'CLI=(eza); UCLI_RUNTIME=(gum); DEV_CLI=(); DEV=(); GAMING=()' >"$HOME/.config/ucli/packages.bash"
  echo 'PERSONAL_PKGS=(spotify)' >"$HOME/.config/ucli/packages.local.bash"
  echo 'BACKUP_UUID=x' >"$HOME/.config/ucli/backup.local.bash"
  echo 'my@addon' >"$HOME/.config/ucli/firefox/personal-extensions.txt"
  echo 'unpushed work' >"$HOME/.local/share/chezmoi/.git/HEAD"
  echo 'mine' >"$HOME/Documents/notes.txt"
  stub sudo '"$@"'
  stub pacman 'case $1 in -Q) [[ $2 == eza || $2 == chezmoi ]] ;; *) exit 0 ;; esac'
}

test_deployed_files_go_and_the_repo_stays() {
  deployed_home
  t_run uninstall --yes --no-snapshot
  assert_status 0
  assert_no_file "$HOME/.zshrc"
  assert_no_file "$HOME/.local/bin/ucli"
  assert_no_file "$HOME/.oh-my-zsh"
  assert_no_file "$HOME/.config/chezmoi"
  assert_eq "unpushed work" "$(cat "$HOME/.local/share/chezmoi/.git/HEAD")"
  assert_contains "$T_OUT" "The dotfiles repository is still at $HOME/.local/share/chezmoi"
  assert_eq "mine" "$(cat "$HOME/Documents/notes.txt")"
}

test_personal_files_survive_inside_the_ucli_config() {
  deployed_home
  t_run uninstall --yes --no-snapshot
  assert_eq "PERSONAL_PKGS=(spotify)" "$(cat "$HOME/.config/ucli/packages.local.bash")"
  assert_eq "BACKUP_UUID=x" "$(cat "$HOME/.config/ucli/backup.local.bash")"
  assert_eq "my@addon" "$(cat "$HOME/.config/ucli/firefox/personal-extensions.txt")"
  assert_no_file "$HOME/.config/ucli/justfile"
  assert_no_file "$HOME/.config/ucli/packages.bash"
  assert_no_file "$HOME/.config/ucli/firefox/user.js"
  assert_no_file "$HOME/.config/ucli/recipes"
  assert_contains "$T_OUT" "(kept: $HOME/.config/ucli/packages.local.bash)"
}

test_ucli_packages_and_chezmoi_are_removed() {
  deployed_home
  stub chezmoi
  t_run uninstall --yes --no-snapshot
  assert_called "pacman -Rns --noconfirm eza"
  assert_called "pacman -Rns --noconfirm chezmoi"
  assert_not_called "pacman -Rns --noconfirm gum"
}

test_declining_removes_nothing() {
  deployed_home
  t_run uninstall </dev/null
  assert_status 0
  assert_contains "$T_OUT" "aborted."
  assert_file "$HOME/.zshrc"
}

test_under_sudo_the_users_home_is_the_target() {
  deployed_home
  local me; me="$(id -un)"
  export SUDO_USER="$me"
  stub getent "echo '$me:x:1000:1000::$HOME:/bin/bash'"
  local fake_root="$T_ROOT/roothome"; mkdir -p "$fake_root"; : >"$fake_root/.zshrc"
  HOME="$fake_root" t_run uninstall --yes --no-snapshot
  assert_no_file "$HOME/.zshrc"
  assert_file "$fake_root/.zshrc"
}

test_arguments() {
  t_run uninstall --bogus
  assert_status 2
  t_run uninstall --help
  assert_contains "$T_OUT" "usage: uninstall.sh"
}

t_main
