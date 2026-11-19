#!/usr/bin/env bash
# doctor.sh: read-only health report. MISSING fails the run, WARN does not, and
# before a desktop exists the shell layer's absence is expected, not a fault.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

doctor() { ( source ../private_dot_local/share/ucli/scripts/check/executable_doctor.sh "$@" ); }

# Every run: only stubbed tools exist, no desktop session, no host ZSH_CUSTOM,
# and /etc is an empty fake tree.
isolate() {
  t_minimal_path
  unset XDG_CURRENT_DESKTOP ZSH_CUSTOM
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
}

# healthy — the files and tools of a fully set-up machine.
healthy() {
  local tool
  for tool in chezmoi zsh starship fastfetch just gum pipx gext paru flatpak pacman; do stub "$tool"; done
  t_config_file justfile <<<'default:'
  t_config_file packages.bash <<<'PERSONAL_PKGS=(); PERSONAL_FLATPAKS=(); PERSONAL_GNOME_EXTENSIONS=()'
  echo 'export PATH="$HOME/.local/bin:$PATH"' >"$HOME/.bash_profile"
  : >"$HOME/.zshrc"
  mkdir -p "$HOME/.config/zsh/conf.d" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git"
  echo 'zsh-users/zsh-autosuggestions' >"$HOME/.config/zsh/plugins.txt"
  : >"$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : >"$HOME/.config/starship.toml"
  mkdir -p "$UCLI_ETC_ROOT/etc/snapper/configs"
  : >"$UCLI_ETC_ROOT/etc/snapper/configs/root"
}

test_a_healthy_machine_passes_with_only_warnings() {
  isolate; healthy
  t_run doctor
  assert_status 0
  assert_contains "$T_OUT" "OK         chezmoi diff empty (deployed)"
  assert_contains "$T_OUT" "OK         zsh plugins (from plugins.txt)"
  assert_contains "$T_OUT" "OK         snapper root config"
  assert_contains "$T_OUT" "WARN       firefox missing"
  assert_contains "$T_OUT" "doctor: ok ("
  assert_not_contains "$T_OUT" "MISSING"
}

test_a_console_only_box_notes_the_shell_layer_instead_of_failing_it() {
  isolate
  t_run doctor
  assert_status 1
  assert_contains "$T_OUT" "MISSING    chezmoi (run install.sh)"
  assert_contains "$T_OUT" "MISSING    .config/ucli/justfile"
  assert_contains "$T_OUT" ".zshrc (run: ucli chezmoi-apply) — expected on a console-only box"
  assert_contains "$T_OUT" "zsh (run: ucli cli) — expected on a console-only box"
  assert_not_contains "$T_OUT" "MISSING    .zshrc"
}

test_once_a_desktop_exists_the_shell_layer_is_required() {
  isolate
  stub gnome-shell
  t_run doctor
  assert_status 1
  assert_contains "$T_OUT" "MISSING    .zshrc (run: ucli chezmoi-apply)"
  assert_contains "$T_OUT" "MISSING    zsh (run: ucli cli)"
}

test_undeployed_changes_and_missing_plugins_are_reported() {
  isolate; healthy
  stub chezmoi '[[ "$1" == diff ]] && echo "--- a/.zshrc"; exit 0'
  rm -rf "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  t_run doctor
  assert_status 1
  assert_contains "$T_OUT" "WARN       chezmoi diff is not empty"
  assert_contains "$T_OUT" "MISSING    zsh plugins: zsh-autosuggestions"
}

test_gnome_counts_extensions_not_quote_characters() {
  isolate; healthy
  export XDG_CURRENT_DESKTOP=GNOME
  stub gsettings "echo \"['dash@example.org', 'blur@example.org', 'caffeine@example.org']\""
  t_run doctor
  assert_contains "$T_OUT" "gnome: 3 extensions enabled"
  stub gsettings 'echo "@as []"'
  t_run doctor
  assert_contains "$T_OUT" "gnome: 0 extensions enabled"
}

test_the_personal_overlay_is_counted() {
  isolate; healthy
  t_config_file packages.local.bash <<<'PERSONAL_PKGS=(spotify steam); PERSONAL_FLATPAKS=(org.gimp.GIMP)'
  t_run doctor
  assert_contains "$T_OUT" "packages.local.bash: 2 package(s), 1 flatpak(s), 0 extension(s)"
}

test_an_overlay_without_packages_bash_is_a_finding_not_a_crash() {
  isolate; healthy
  rm "$HOME/.config/ucli/packages.bash"
  t_config_file packages.local.bash <<<'PERSONAL_PKGS=(spotify)'
  t_run doctor
  assert_status 1
  assert_contains "$T_OUT" "MISSING    .config/ucli/packages.bash"
  assert_contains "$T_OUT" "doctor: "
}

test_committed_gates_are_listed() {
  isolate; healthy
  mkdir -p "$XDG_STATE_HOME/ucli/gates/user"
  echo 3 >"$XDG_STATE_HOME/ucli/gates/user/gnome-extensions"
  t_run doctor
  assert_contains "$T_OUT" "gate user/gnome-extensions = 3"
}

test_the_dev_box_is_checked_for_provisioning() {
  isolate; healthy
  stub distrobox 'case "$1" in
    list)  echo "ID | NAME | STATUS"; echo "abc | dev | Up" ;;
    enter) echo "12.9|v22.11.0|8.4.3" ;;
  esac'
  t_run doctor
  assert_contains "$T_OUT" "OK         dev: debian 12.9 / node v22.11.0 / php 8.4.3"
  stub distrobox 'case "$1" in
    list)  echo "abc | dev | Up" ;;
    enter) echo "12.9|MISSING|MISSING" ;;
  esac'
  t_run doctor
  assert_contains "$T_OUT" "WARN       dev exists but is not provisioned (node MISSING, php MISSING)"
}

t_main
