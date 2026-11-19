#!/usr/bin/env bash
# gnome-defaults.sh: "default, not lock". A key is set when it still holds the
# schema default, kept when the user changed it (unless --force), skipped when
# its schema, key or required file is missing; --status and --dry-run write
# nothing. gsettings is a stateful fake: schema defaults and user values live in
# files, and GSETTINGS_BACKEND=memory reads the defaults, as the real one does.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

defaults() { ( source ../private_dot_local/share/ucli/scripts/install/executable_gnome-defaults.sh "$@" ); }

# schema <schema> <key> <default> — install a key in the fake schema database.
schema() {
  mkdir -p "$GS/default/$1"
  printf '%s' "$3" >"$GS/default/$1/$2"
}
# user_value <schema> <key> <value> — what the user's dconf holds.
user_value() { mkdir -p "$GS/user/$1"; printf '%s' "$3" >"$GS/user/$1/$2"; }
value_of() { cat "$GS/user/$1/$2" 2>/dev/null || cat "$GS/default/$1/$2"; }

fake_gsettings() {
  export GS="$T_ROOT/gs"
  mkdir -p "$GS/default" "$GS/user"
  stub gsettings 'case $1 in
    list-schemas) ls "$GS/default" ;;
    list-keys)    ls "$GS/default/$2" ;;
    get)  if [[ ${GSETTINGS_BACKEND:-} == memory || ! -e $GS/user/$2/$3 ]]; then cat "$GS/default/$2/$3"; else cat "$GS/user/$2/$3"; fi; echo ;;
    set)  [[ ${FAKE_SET_IGNORED:-0} == 1 ]] && exit 0; mkdir -p "$GS/user/$2"; printf "%s" "$4" >"$GS/user/$2/$3" ;;
  esac'
  schema org.gnome.mutter center-new-windows false
  schema org.gnome.desktop.interface enable-hot-corners true
  schema org.gnome.desktop.interface clock-show-weekday false
}

test_untouched_keys_are_set_to_the_curated_value() {
  fake_gsettings
  t_run defaults --no-restart
  assert_status 0
  assert_eq "true" "$(value_of org.gnome.mutter center-new-windows)"
  assert_eq "false" "$(value_of org.gnome.desktop.interface enable-hot-corners)"
  assert_contains "$T_OUT" "gnome defaults: 3 set, 0 already correct, 0 yours (kept)"
}

test_a_value_the_user_chose_is_kept_unless_forced() {
  fake_gsettings
  user_value org.gnome.mutter center-new-windows maybe
  t_run defaults --no-restart
  assert_contains "$T_OUT" "keep    org.gnome.mutter center-new-windows = maybe (yours, not the repo's true)"
  assert_eq "maybe" "$(value_of org.gnome.mutter center-new-windows)"
  t_run defaults --no-restart --force
  assert_eq "true" "$(value_of org.gnome.mutter center-new-windows)"
}

test_correct_values_are_counted_not_rewritten() {
  fake_gsettings
  user_value org.gnome.desktop.interface clock-show-weekday true
  t_run defaults --no-restart
  assert_contains "$T_OUT" "1 already correct"
  assert_not_called "gsettings set org.gnome.desktop.interface clock-show-weekday"
}

test_missing_schemas_and_keys_are_skipped() {
  fake_gsettings
  t_run defaults --no-restart --status
  assert_contains "$T_OUT" "skip    org.gnome.shell.extensions.dash-to-dock"
  assert_contains "$T_OUT" "— schema not installed"
  schema org.gnome.desktop.interface some-other-key x   # schema exists, accent-color does not
  t_run defaults --no-restart --status
  assert_contains "$T_OUT" "skip    org.gnome.desktop.interface accent-color — key not in this version"
}

test_a_value_that_needs_a_file_is_skipped_without_it() {
  fake_gsettings
  schema org.gnome.desktop.interface gtk-theme "'Adwaita'"
  t_run defaults --no-restart --status
  if [[ -e /usr/share/themes/adw-gtk3-dark ]]; then
    assert_contains "$T_OUT" "set     org.gnome.desktop.interface gtk-theme: 'Adwaita' -> 'adw-gtk3-dark'"
  else
    assert_contains "$T_OUT" "skip    org.gnome.desktop.interface gtk-theme — needs /usr/share/themes/adw-gtk3-dark"
  fi
}

test_status_and_dry_run_write_nothing() {
  fake_gsettings
  t_run defaults --status
  assert_status 0
  assert_contains "$T_OUT" "set     org.gnome.mutter center-new-windows: false -> true"
  t_run defaults --dry-run
  assert_contains "$T_OUT" "+ gsettings set org.gnome.mutter center-new-windows true"
  assert_contains "$T_OUT" "3 to set"
  assert_not_called "gsettings set"
}

test_a_set_that_does_not_stick_is_a_failure() {
  fake_gsettings
  export FAKE_SET_IGNORED=1
  t_run defaults --no-restart
  assert_status 1
  assert_contains "$T_OUT" "warning: org.gnome.mutter center-new-windows is false after setting it to true"
  assert_contains "$T_OUT" "some settings could not be applied"
}

test_a_running_nautilus_is_restarted_for_its_extensions() {
  fake_gsettings
  stub nautilus; stub pgrep 'exit 0'
  t_run defaults
  assert_called "nautilus -q"
  assert_contains "$T_OUT" "nautilus restarted"
  t_run defaults --no-restart
  [[ "$(grep -c 'nautilus -q' "$T_CALLS")" == 1 ]] || t_die "--no-restart must not restart Nautilus"
}

test_without_gsettings_and_bad_arguments() {
  t_minimal_path
  t_run defaults
  assert_status 1
  assert_contains "$T_OUT" "gsettings not found"
  t_run defaults --bogus
  assert_status 2
}

t_main
