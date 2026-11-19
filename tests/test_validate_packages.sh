#!/usr/bin/env bash
# validate-packages.sh: every array name resolves through pacman or the AUR,
# extension lists are PK:UUID, and the personal overlay is checked as well.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

validate() { ( source ../private_dot_local/share/ucli/scripts/install/executable_validate-packages.sh "$@" ); }

# repo-* is a pacman package, group-* a pacman group, aur-* only in the AUR
# (aur_exists asks python3, whose first argument is "-" for the heredoc).
fake_world() {
  stub pacman 'case "$1" in
    -Si)  [[ "$2" == repo-* ]] ;;
    -Sgq) [[ "$2" == group-* ]] ;;
    *)    exit 1 ;;
  esac'
  stub python3 '[[ "$2" == aur-* ]]'
  stub curl '[[ "${T_CURL_OK:-1}" == 1 ]]'
}

test_every_kind_of_name_resolves() {
  fake_world
  t_config_file packages.bash <<'EOF'
BOOTSTRAP=(repo-base group-devel aur-helper)
GNOME_MANAGED_EXTENSIONS=("1234:dash@example.org")
EOF
  t_run validate
  assert_status 0
  assert_contains "$T_OUT" "OK repo package: repo-base"
  assert_contains "$T_OUT" "OK repo group:   group-devel"
  assert_contains "$T_OUT" "OK AUR:          aur-helper"
  assert_contains "$T_OUT" "OK extension: 1234 (dash@example.org)"
}

test_a_missing_name_fails_but_the_rest_are_still_checked() {
  fake_world
  t_config_file packages.bash <<'EOF'
BOOTSTRAP=(nowhere repo-base)
CLI=(repo-eza)
EOF
  t_run validate
  assert_status 1
  assert_contains "$T_OUT" "MISSING:         nowhere"
  assert_contains "$T_OUT" "OK repo package: repo-base"
  assert_contains "$T_OUT" "OK repo package: repo-eza"
}

test_the_personal_overlay_is_validated_too() {
  fake_world
  t_config_file packages.bash <<'EOF'
BOOTSTRAP=(repo-base)
PERSONAL_PKGS=()
PERSONAL_GNOME_EXTENSIONS=()
EOF
  t_config_file packages.local.bash <<'EOF'
PERSONAL_PKGS=(typo-pkg)
PERSONAL_GNOME_EXTENSIONS=("no-colon-here")
EOF
  t_run validate
  assert_status 1
  assert_contains "$T_OUT" "MISSING:         typo-pkg"
  assert_contains "$T_OUT" "MALFORMED (want PK:UUID): no-colon-here"
}

test_an_unreachable_extension_api_still_accepts_numeric_pks() {
  fake_world
  export T_CURL_OK=0
  t_config_file packages.bash <<'EOF'
GNOME_MANAGED_EXTENSIONS=("42:numeric@example.org" "abc:word@example.org")
EOF
  t_run validate
  assert_status 1
  assert_contains "$T_OUT" "OK extension: 42 (numeric@example.org)"
  assert_contains "$T_OUT" "MISSING extension pk: abc"
}

test_a_missing_packages_bash_says_how_to_fix_it() {
  fake_world
  t_run validate
  assert_eq 1 "$T_STATUS" "a missing packages.bash must fail"
  assert_contains "$T_OUT" "chezmoi apply"
  assert_not_called "pacman"
}

test_arguments() {
  fake_world
  t_run validate --bogus
  assert_status 2
  assert_contains "$T_OUT" "unknown argument: --bogus"
  t_run validate --help
  assert_status 0
  assert_contains "$T_OUT" "Check every name in every package array"
}

test_the_shipped_packages_bash_defines_every_validated_array() {
  # Every name validate-packages.sh walks must exist (possibly empty) in the
  # real packages.bash; an undefined one would be silently skipped.
  local names name
  names="$(sed -n '/^package_arrays=(/,/^)/p' "$T_SCRIPTS/install/executable_validate-packages.sh" | sed -e '1d' -e '/^)/d')"
  # shellcheck source=../private_dot_config/ucli/packages.bash
  source "$T_CONFIG/packages.bash"
  for name in $names GNOME_MANAGED_EXTENSIONS PERSONAL_GNOME_EXTENSIONS; do
    declare -p "$name" >/dev/null 2>&1 || t_die "packages.bash does not define $name"
  done
}

t_main
