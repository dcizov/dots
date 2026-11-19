#!/usr/bin/env bash
# install-shell.sh / install-oh-my-zsh.sh: the shell tier — tools present,
# oh-my-zsh in place, every plugin in plugins.txt cloned or updated, and zsh
# as the login shell.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

shell_tier() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-shell.sh "$@" ); }
omz() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-oh-my-zsh.sh "$@" ); }

# box — the four tools, a passwd entry whose shell chsh changes, plugins.txt.
box() {
  export USER=alice SH_FILE="$T_ROOT/login-shell"
  echo /bin/bash >"$SH_FILE"
  local t; for t in zsh curl starship; do stub "$t"; done
  stub git '[[ $1 == clone ]] && mkdir -p "${@: -1}/.git"; exit 0'
  stub getent 'echo "alice:x:1000:1000::$HOME:$(cat "$SH_FILE")"'
  stub chsh 'echo "$2" >"$SH_FILE"'
  stub sudo '"$@"'
  mkdir -p "$HOME/.config/zsh/conf.d"
  printf '# the one list\nzsh-users/zsh-autosuggestions\nzdharma-continuum/fast-syntax-highlighting  # colours\n' >"$HOME/.config/zsh/plugins.txt"
  : >"$HOME/.config/starship.toml"
  S="$(t_deployed install/install-shell)"
  t_fake_script "${S%/*}/install-packages.sh"
  t_fake_script "${S%/*}/install-oh-my-zsh.sh"
}

test_the_shell_tier_installs_plugins_and_switches_the_login_shell() {
  box
  t_run bash "$S"
  assert_status 0
  assert_called "install-packages.sh shell-tools"
  assert_called "install-oh-my-zsh.sh"
  assert_called "git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git"
  assert_called "git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
  assert_eq "$(command -v zsh)" "$(cat "$SH_FILE")"
}

test_a_rerun_pulls_instead_of_cloning_and_keeps_the_shell() {
  box
  bash "$S" >/dev/null 2>&1
  : >"$T_CALLS"
  t_run bash "$S"
  assert_status 0
  assert_called "git -C $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions pull --ff-only"
  assert_not_called "git clone"
  assert_not_called "chsh"
}

test_skip_packages_and_a_missing_tool() {
  box
  rm "$T_BIN/starship"
  t_minimal_path
  for t in zsh curl git getent; do [[ -e "$T_BIN/$t" ]] || t_die "lost stub $t"; done
  UCLI_SKIP_PACKAGES=1 t_run bash "$S"
  assert_status 1
  assert_not_called "install-packages.sh"
  assert_contains "$T_OUT" "error: 'starship' is missing"
}

test_without_plugins_txt_chezmoi_deploys_the_shell_layer() {
  box
  rm "$HOME/.config/zsh/plugins.txt"
  stub chezmoi 'printf "zsh-users/zsh-completions\n" >"$HOME/.config/zsh/plugins.txt"'
  t_run bash "$S"
  assert_status 0
  assert_called "chezmoi apply -- $HOME/.zshrc $HOME/.config/zsh $HOME/.config/starship.toml"
  assert_called "git clone --depth=1 https://github.com/zsh-users/zsh-completions.git"
}

test_a_failed_chsh_is_reported() {
  box
  stub chsh 'exit 1'
  t_run bash "$S"
  assert_status 0
  assert_contains "$T_OUT" "warning: chsh failed; run: sudo chsh -s"
  assert_contains "$T_OUT" "login shell is still /bin/bash"
}

test_oh_my_zsh_installs_where_it_checks() {
  t_minimal_path
  stub zsh; stub git
  stub curl 'echo "echo \"installing into \$ZSH\" >>\"\$T_CALLS\""'
  export UCLI_REAL_HOME="$T_ROOT/realhome"
  t_run omz
  assert_status 0
  assert_called "installing into $T_ROOT/realhome/.oh-my-zsh"
  mkdir -p "$T_ROOT/realhome/.oh-my-zsh/.git"; : >"$T_ROOT/realhome/.oh-my-zsh/oh-my-zsh.sh"
  t_run omz
  assert_contains "$T_OUT" "Oh My Zsh already installed"
}

test_oh_my_zsh_and_the_shell_tier_need_their_tools() {
  t_minimal_path
  t_run omz
  assert_status 1
  assert_contains "$T_OUT" "missing required command: zsh"
  UCLI_SKIP_PACKAGES=1 t_run shell_tier
  assert_status 1
  assert_contains "$T_OUT" "error: 'zsh' is missing; run: ucli cli"
}

t_main
