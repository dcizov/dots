#!/usr/bin/env bash
# install.sh: the console bootstrap. Arguments, the Arch-family gate, the exact
# pacman/chezmoi calls, the console-only apply, and the post-bootstrap snapshot.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

bootstrap() { ( source ../install.sh "$@" ); }

PKGS="ca-certificates curl git chezmoi just"
DEFAULT_REPO="https://github.com/dcizov/dots.git"

# fake_os <ID> [ID_LIKE] — an /etc tree under UCLI_ETC_ROOT; sudo runs its
# arguments, pacman and chezmoi only record that they were called.
fake_os() {
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
  printf 'ID=%s\nID_LIKE=%s\n' "$1" "${2:-}" >"$UCLI_ETC_ROOT/etc/os-release"
  stub sudo '"$@"'
  stub pacman
  stub chezmoi
}

test_dry_run_prints_the_plan_and_changes_nothing() {
  fake_os arch
  t_run bootstrap --dry-run
  assert_status 0
  assert_contains "$T_OUT" "[dry-run] would run: sudo pacman -S --needed $PKGS"
  assert_contains "$T_OUT" "[dry-run] would run: chezmoi init $DEFAULT_REPO"
  assert_contains "$T_OUT" "chezmoi apply -v $HOME/.local/bin/ucli $HOME/.config/ucli $HOME/.local/share/ucli $HOME/.bash_profile"
  assert_not_called "pacman"
  assert_not_called "chezmoi"
}

test_branch_and_repo_flags_reach_chezmoi_init() {
  fake_os arch
  t_run bootstrap --dry-run --branch dev --repo=https://example.org/fork.git
  assert_status 0
  assert_contains "$T_OUT" "Branch: dev"
  assert_contains "$T_OUT" "would run: chezmoi init --branch dev https://example.org/fork.git"
}

test_an_option_without_its_value_is_a_usage_error() {
  fake_os arch
  t_run bootstrap --repo
  assert_status 2
  assert_contains "$T_OUT" "--repo needs a value"
  t_run bootstrap --branch --dry-run
  assert_status 2
  assert_contains "$T_OUT" "--branch needs a value"
}

test_unknown_arguments_and_help() {
  fake_os arch
  t_run bootstrap --bogus
  assert_status 2
  assert_contains "$T_OUT" "unknown argument: --bogus"
  t_run bootstrap --help
  assert_status 0
  assert_contains "$T_OUT" "usage: install.sh"
}

test_arch_derivatives_continue_with_a_warning() {
  fake_os endeavouros arch
  t_run bootstrap --dry-run
  assert_status 0
  assert_contains "$T_OUT" "'endeavouros' is Arch-based (ID_LIKE=arch)"
  assert_contains "$T_OUT" "would run: sudo pacman -S --needed"
}

test_non_arch_systems_are_refused_before_anything_installs() {
  fake_os ubuntu debian
  t_run bootstrap --yes
  assert_status 1
  assert_contains "$T_OUT" "unsupported distro: ubuntu (ID_LIKE=debian)"
  assert_not_called "pacman"
  assert_not_called "chezmoi"
}

test_a_real_run_installs_inits_and_applies_only_the_console_targets() {
  fake_os cachyos arch
  t_run bootstrap --yes --no-snapshot
  assert_status 0
  assert_called "pacman -S --needed $PKGS"
  assert_called "chezmoi init $DEFAULT_REPO"
  assert_called "chezmoi apply -v $HOME/.local/bin/ucli $HOME/.config/ucli $HOME/.local/share/ucli $HOME/.bash_profile"
  assert_not_called "pacman -Syu"
  assert_contains "$T_OUT" "skipping the post-bootstrap snapshot"
  assert_file "$HOME/.local/bin"
}

test_no_apply_inits_without_deploying() {
  fake_os arch
  t_run bootstrap --yes --no-apply --no-snapshot
  assert_status 0
  assert_called "chezmoi init"
  assert_not_called "chezmoi apply"
}

test_a_failed_apply_warns_and_carries_on() {
  fake_os arch
  stub chezmoi '[[ "$1" != apply ]]'
  t_run bootstrap --yes --no-snapshot
  assert_status 0
  assert_contains "$T_OUT" "chezmoi apply failed; run 'ucli chezmoi-apply'"
  assert_contains "$T_OUT" "Next, in this order:"
}

test_the_snapshot_runs_only_when_snapper_and_the_script_exist() {
  fake_os arch
  t_run bootstrap --yes
  assert_contains "$T_OUT" "no snapper config yet"

  mkdir -p "$UCLI_ETC_ROOT/etc/snapper/configs"
  : >"$UCLI_ETC_ROOT/etc/snapper/configs/root"
  t_run bootstrap --yes
  assert_contains "$T_OUT" "snapshot script not deployed yet"

  local script="$HOME/.local/share/ucli/scripts/system/snapshot-fresh-install.sh"
  mkdir -p "$(dirname "$script")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "snapshot $*" >>"$T_CALLS"\n' >"$script"
  chmod +x "$script"
  t_run bootstrap --yes
  assert_status 0
  assert_called "sudo $script post-bootstrap"
  assert_called "snapshot post-bootstrap"

  UCLI_NO_SNAPSHOT=1 t_run bootstrap --yes
  assert_contains "$T_OUT" "skipping the post-bootstrap snapshot"
}

test_declining_the_prompt_changes_nothing() {
  fake_os arch
  t_run bootstrap <<<"n"
  assert_status 0
  assert_not_called "pacman"
  assert_not_called "chezmoi"
}

t_main
