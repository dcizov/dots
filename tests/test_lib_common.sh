#!/usr/bin/env bash
# lib/common.sh: privilege and lookup helpers, the real user's home under
# sudo, the packages.bash + overlay loader, and header-comment help text.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

common() { source ../private_dot_local/share/ucli/scripts/lib/common.sh; }

test_as_root_uses_sudo_only_when_not_root() {
  common
  stub sudo '"$@"'
  t_run as_root echo hi
  assert_eq "hi" "$T_OUT"
  if ((EUID == 0)); then assert_not_called "sudo"; else assert_called "sudo echo hi"; fi
}

test_have() {
  common
  stub ucli-test-tool
  have ucli-test-tool || t_die "have missed a command on PATH"
  ! have ucli-no-such-tool-xyz || t_die "have found a command that does not exist"
}

test_confirm_skips_the_prompt_with_yes_flag() {
  common
  # shellcheck disable=SC2329  # called by confirm
  ui_confirm() { echo "asked: $1"; return 1; }
  yes_flag=1
  t_run confirm "go?"
  assert_status 0
  assert_eq "" "$T_OUT" "--yes must not prompt"
  yes_flag=0
  t_run confirm "go?"
  assert_status 1
  assert_eq "asked: go?" "$T_OUT"
}

test_real_home_is_HOME_without_sudo() {
  common
  assert_eq "$HOME" "$(ucli_real_home)"
}

test_real_home_follows_SUDO_USER() {
  common
  local me expected
  me="$(id -un)"
  expected="$(getent passwd "$me" | cut -d: -f6)"
  export SUDO_USER="$me"
  assert_eq "$me" "$(ucli_real_user)"
  assert_eq "$expected" "$(ucli_real_home)" "under sudo the passwd home wins over \$HOME"
}

test_load_packages_reads_the_overlay_after_the_base() {
  common
  t_config_file packages.bash <<'EOF'
AUR_HELPER=""
PERSONAL_PKGS=()
CLI=(eza)
EOF
  t_config_file packages.local.bash <<'EOF'
AUR_HELPER="paru"
PERSONAL_PKGS=(spotify)
EOF
  ucli_load_packages
  assert_eq "paru" "$AUR_HELPER" "the overlay must override packages.bash"
  assert_eq "spotify" "${PERSONAL_PKGS[*]}"
  assert_eq "eza" "${CLI[*]}"
}

test_load_packages_without_an_overlay() {
  common
  t_config_file packages.bash <<<'CLI=(bat)'
  ucli_load_packages
  assert_eq "bat" "${CLI[*]}"
}

test_load_packages_fails_without_packages_bash() {
  common
  t_run ucli_load_packages
  assert_status 1
  assert_contains "$T_OUT" "packages.bash is missing"
}

test_load_packages_takes_an_explicit_home() {
  common
  local other="$T_ROOT/other"
  mkdir -p "$other/.config/ucli"
  echo 'CLI=(fd)' >"$other/.config/ucli/packages.bash"
  ucli_load_packages "$other"
  assert_eq "fd" "${CLI[*]}"
}

test_script_help_prints_the_callers_header() {
  common
  local script="$T_ROOT/sample.sh"
  cat >"$script" <<'EOF'
#!/usr/bin/env bash
# sample.sh — does one thing.
#
#   sample.sh --flag   explained
set -eu
show() { ucli_script_help; }
range() { ucli_script_help 2 3; }
EOF
  # shellcheck source=/dev/null
  source "$script"
  assert_eq $'sample.sh — does one thing.\n\n  sample.sh --flag   explained' "$(show)"
  # lines 2..3: the summary and the blank "#" after it ($(…) drops the newline)
  assert_eq 'sample.sh — does one thing.' "$(range)"
  assert_eq 2 "$(range | wc -l)"
}

t_main
