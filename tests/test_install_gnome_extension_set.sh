#!/usr/bin/env bash
# install-gnome-extension-set.sh: install the set through gext, enable it with
# one write to enabled-extensions (keeping what the user enabled), commit the
# gate only for a complete set, and prune what left the arrays — but never an
# extension the user installed. gext, gnome-extensions and dconf are stateful
# fakes over files in $GX.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

extset() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-gnome-extension-set.sh "$@" ); }

# shell — FAKE_EGO maps "pk:uuid" for what extensions.gnome.org serves,
# FAKE_BROKEN lists pks whose install fails.
shell() {
  export GX="$T_ROOT/gx" FAKE_EGO="${FAKE_EGO:-11:dock@x 22:blur@y 33:mine@me}" FAKE_BROKEN="${FAKE_BROKEN:-}"
  mkdir -p "$GX"; : >"$GX/installed"; echo "@as []" >"$GX/enabled"
  stub gext 'case $1 in
    list) cat "$GX/installed" ;;
    install) [[ " $FAKE_BROKEN " == *" $2 "* ]] && { echo "HTTP 500" >&2; exit 1; }
      for m in $FAKE_EGO; do [[ ${m%%:*} == "$2" ]] && echo "${m#*:}" >>"$GX/installed"; done ;;
    enable) ;;
  esac
  exit 0'
  stub gnome-extensions 'case $1 in
    list) cat "$GX/installed" ;;
    uninstall) grep -vx "$2" "$GX/installed" >"$GX/i2"; mv "$GX/i2" "$GX/installed" ;;
  esac'
  stub dconf 'case $1 in read) cat "$GX/enabled" ;; write) echo "$3" >"$GX/enabled" ;; esac'
}
enabled() { cat "$GX/enabled"; }
user_installed() { echo "$1" >>"$GX/installed"; mkdir -p "$HOME/.local/share/gnome-shell/extensions/$1"; }
packages() { t_config_file packages.bash <<<"GNOME_MANAGED_EXTENSIONS=($1)
PERSONAL_GNOME_EXTENSIONS=()"; }
personal() { t_config_file packages.local.bash <<<"PERSONAL_GNOME_EXTENSIONS=($1)"; }

test_the_personal_set_installs_and_enables_in_one_write() {
  shell; packages ""; personal "11:dock@x 22:blur@y"
  echo "['already@user']" >"$GX/enabled"
  t_run extset personal
  assert_status 0
  assert_called "gext install 11"
  assert_called "gext install 22"
  assert_eq "['already@user', 'dock@x', 'blur@y']" "$(enabled)"
  assert_eq 1 "$(grep -c 'dconf write' "$T_CALLS")" "enabled-extensions is written once"
  assert_contains "$T_OUT" "done: 2 extension(s) installed and enabled."
}

test_an_unchanged_set_is_skipped_and_a_broken_one_retried() {
  shell; packages ""; personal "11:dock@x"
  extset personal >/dev/null 2>&1
  t_run extset personal
  assert_contains "$T_OUT" "unchanged since the last run"
  # the user disables it by hand: the gate must not hide that
  echo "@as []" >"$GX/enabled"
  t_run extset personal
  assert_contains "$T_OUT" "recorded as done but is not installed/enabled; re-applying."
  assert_eq "['dock@x']" "$(enabled)"
}

test_a_failed_install_is_not_enabled_and_not_recorded() {
  export FAKE_BROKEN=22
  shell; packages ""; personal "11:dock@x 22:blur@y"
  t_run extset personal
  assert_status 1
  assert_contains "$T_OUT" "could not install extension pk=22 (blur@y)"
  assert_contains "$T_OUT" "incomplete (1 of 2 installed)"
  assert_eq "['dock@x']" "$(enabled)"
  unset FAKE_BROKEN; export FAKE_BROKEN=""
  t_run extset personal
  assert_status 0
  assert_contains "$T_OUT" "dock@x) already installed; skipping"
}

test_removing_an_extension_from_the_list_prunes_only_ours() {
  shell; packages ""; personal "11:dock@x 22:blur@y"
  extset personal >/dev/null 2>&1
  for u in dock@x blur@y; do mkdir -p "$HOME/.local/share/gnome-shell/extensions/$u"; done
  user_installed mine@me
  echo "['dock@x', 'blur@y', 'mine@me']" >"$GX/enabled"
  personal "11:dock@x"
  t_run extset personal
  assert_status 0
  assert_contains "$T_OUT" "prune: no longer in the managed or personal set:"
  assert_contains "$T_OUT" "removed blur@y (user extension)"
  assert_eq "['dock@x', 'mine@me']" "$(enabled)"
  assert_contains "$(cat "$GX/installed")" "mine@me"
  assert_not_contains "$(cat "$GX/installed")" "blur@y"
}

test_an_emptied_set_still_prunes_then_stops() {
  shell; packages ""; personal "11:dock@x"
  extset personal >/dev/null 2>&1
  personal ""
  t_run extset personal
  assert_status 0
  assert_contains "$T_OUT" "dock@x was already gone; dropped its enabled entry"
  assert_contains "$T_OUT" "set 'personal' is empty; nothing to install."
  assert_eq "[]" "$(enabled)"
}

test_no_overlay_means_no_personal_set_and_no_gext_needed() {
  t_minimal_path
  packages ""
  t_run extset personal
  assert_status 0
  assert_contains "$T_OUT" "no ~/.config/ucli/packages.local.bash; nothing personal to install."
}

test_without_gext_the_fix_is_named() {
  t_minimal_path; stub dconf
  packages ""; personal "11:dock@x"
  t_run extset personal
  assert_status 1
  assert_contains "$T_OUT" "run: ucli install-gnome-extensions-cli"
}

test_the_managed_set_includes_gradia_capture() {
  shell; packages "11:dock@x"
  S="$(t_deployed install/install-gnome-extension-set)"
  t_fake_script "${S%/*}/install-gradia-capture.sh" 'echo gradia-integration@alexandervanhee.github.io >>"$GX/installed"'
  t_run bash "$S" managed
  assert_status 0
  assert_called "install-gradia-capture.sh"
  assert_eq "['dock@x', 'gradia-integration@alexandervanhee.github.io']" "$(enabled)"
  t_fake_script "${S%/*}/install-gradia-capture.sh" 'exit 1'
  t_run bash "$S" managed --force
  assert_status 1
  assert_contains "$T_OUT" "gradia-integration@alexandervanhee.github.io (build failed)"
}

test_arguments() {
  t_run extset sideways
  assert_status 2
  t_run extset --help
  assert_contains "$T_OUT" "personal  your own"
}

t_main
