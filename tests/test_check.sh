#!/usr/bin/env bash
# check.sh: every class of mistake it exists to catch, on a minimal fixture
# tree in the repo layout, plus the clean case, the deployed layout and the
# real repository itself.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

check() { ( source ../private_dot_local/share/ucli/scripts/check/executable_check.sh "$@" ); }

# fixture — a tiny but complete source tree under $FX: one lib, the validator
# and installer the array check reads, a justfile with two recipes, zsh config.
fixture() {
  FX="$T_ROOT/repo"
  local s="$FX/private_dot_local/share/ucli/scripts" c="$FX/private_dot_config/ucli"
  mkdir -p "$s/lib" "$s/install" "$c/recipes" "$FX/private_dot_config/zsh/conf.d"
  printf '# shellcheck shell=bash\nhello() { echo hi; }\n' >"$s/lib/greet.sh"
  printf '#!/usr/bin/env bash\npackage_arrays=(\n  CLI\n)\necho "see: ucli hello ${package_arrays[*]}"\n' \
    >"$s/install/executable_validate-packages.sh"
  printf '#!/usr/bin/env bash\nadd_array() { :; }\nadd_array CLI\n' >"$s/install/executable_install-packages.sh"
  printf '# shellcheck disable=SC2034\nCLI=(eza)\n' >"$c/packages.bash"
  printf "import 'recipes/a.just'\n\nhello:\n    @echo hi\n" >"$c/justfile"
  printf 'bye:\n    @echo bye\n' >"$c/recipes/a.just"
  printf 'setopt extendedglob\n' >"$FX/dot_zshrc"
  printf 'alias ll="ls -l"\n' >"$FX/private_dot_config/zsh/conf.d/aliases.zsh"
}

script() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$FX/private_dot_local/share/ucli/scripts/$1"; }

test_a_clean_tree_passes() {
  fixture
  t_run check "$FX"
  assert_status 0
  assert_contains "$T_OUT" "layout=repo"
  assert_contains "$T_OUT" "1 package arrays resolve"
  assert_contains "$T_OUT" "check: ok"
}

test_a_syntax_error_fails_bash_n() {
  fixture
  script lib/broken.sh 'if true; then echo missing fi'
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "bash -n private_dot_local/share/ucli/scripts/lib/broken.sh"
}

test_a_zsh_syntax_error_is_caught() {
  command -v zsh >/dev/null 2>&1 || return 0
  fixture
  printf 'if [[ -n x ]]; then\n' >"$FX/private_dot_config/zsh/conf.d/broken.zsh"
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "zsh -n private_dot_config/zsh/conf.d/broken.zsh"
}

test_a_broken_justfile_is_caught() {
  command -v just >/dev/null 2>&1 || return 0
  fixture
  printf 'hello:\n  @echo one\n    @echo inconsistent indent\n' >"$FX/private_dot_config/ucli/recipes/a.just"
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "just --list:"
}

test_an_array_missing_from_packages_bash_is_caught() {
  fixture
  printf '#!/usr/bin/env bash\nadd_array() { :; }\nadd_array CLI\nadd_array SHELL_DEPS\n' \
    >"$FX/private_dot_local/share/ucli/scripts/install/executable_install-packages.sh"
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" '$SHELL_DEPS is referenced by the scripts but not defined in packages.bash'
}

test_a_stale_ucli_verb_is_caught_but_prose_is_not() {
  fixture
  script lib/msg.sh 'echo "run ucli frobnicate next"; echo "the ucli wrapper is fine"; echo "ucli bye works"'
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "ucli frobnicate is not a recipe"
  assert_not_contains "$T_OUT" "ucli wrapper is not a recipe"
  assert_not_contains "$T_OUT" "ucli bye is not a recipe"
}

test_stale_verbs_in_docs_count_too() {
  fixture
  mkdir -p "$FX/docs"
  printf 'Run `ucli gnome` to start.\n' >"$FX/docs/guide.md"
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "ucli gnome is not a recipe (docs/guide.md"
}

test_a_script_ending_on_a_bare_conditional_is_caught() {
  fixture
  script lib/tail.sh $'x=0\n(( x )) && echo yes'
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "ends with a conditional (false test = exit 1): private_dot_local/share/ucli/scripts/lib/tail.sh"
}

test_an_interactive_command_with_hidden_stderr_is_caught() {
  fixture
  script lib/shell.sh $'chsh -s /usr/bin/zsh 2>/dev/null\ngetent passwd root 2>/dev/null'
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "interactive command with hidden stderr"
  assert_contains "$T_OUT" "chsh -s /usr/bin/zsh 2>/dev/null"
  assert_not_contains "$T_OUT" "getent passwd root"
}

test_a_shellcheck_warning_fails_the_check() {
  command -v shellcheck >/dev/null 2>&1 || return 0
  fixture
  script lib/unused.sh $'unused_var=1\necho "$UNSET_THING"'
  t_run check "$FX"
  assert_status 1
  assert_contains "$T_OUT" "shellcheck private_dot_local/share/ucli/scripts/lib/unused.sh"
}

test_the_deployed_layout_is_recognised() {
  local d="$T_ROOT/home2"
  mkdir -p "$d/.local/share/ucli/scripts/lib" "$d/.config/ucli/recipes"
  printf '# shellcheck shell=bash\n:\n' >"$d/.local/share/ucli/scripts/lib/ok.sh"
  t_run check "$d"
  assert_contains "$T_OUT" "layout=deployed"
}

test_no_ucli_tree_and_bad_options() {
  t_run check "$T_ROOT/nowhere"
  assert_status 1
  assert_contains "$T_OUT" "check: no ucli tree under $T_ROOT/nowhere"
  t_run check --bogus
  assert_status 2
  t_run check --help
  assert_status 0
  assert_contains "$T_OUT" "Offline static checks"
}

test_the_repository_itself_is_clean() {
  t_run check "$(cd .. && pwd)"
  assert_status 0
  assert_contains "$T_OUT" "check: ok"
}

t_main
