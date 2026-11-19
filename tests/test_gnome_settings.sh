#!/usr/bin/env bash
# backup-gnome-settings.sh / restore-gnome-settings.sh: dconf dumps and the
# extension lists round-trip, a failed dump never overwrites a good backup,
# and restore loads only what is there and re-enables through gext.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

backup()  { ( source ../private_dot_local/share/ucli/scripts/install/executable_backup-gnome-settings.sh "$@" ); }
restore() { ( source ../private_dot_local/share/ucli/scripts/install/executable_restore-gnome-settings.sh "$@" ); }

DIR_DEFAULT() { printf '%s' "$HOME/.local/share/ucli/settings/gnome"; }

# A session whose dconf and gnome-extensions answer; FAKE_DCONF=0 breaks dconf.
session() {
  t_minimal_path
  stub dconf 'case $1 in
    dump) [[ ${FAKE_DCONF:-1} == 1 ]] || exit 1; echo "[dumped $2]" ;;
    load) cat >>"${T_CALLS%/*}/loaded"; echo "--" >>"${T_CALLS%/*}/loaded" ;;
  esac'
  stub gnome-extensions '[[ ${2:-} == --enabled ]] && printf "dash@x\nblur@y\n" || printf "dash@x\nblur@y\nold@z\n"'
}

test_backup_writes_every_file() {
  session
  t_run backup
  assert_status 0
  local d; d="$(DIR_DEFAULT)"
  assert_eq "[dumped /org/gnome/desktop/]" "$(cat "$d/desktop.dconf")"
  assert_eq "[dumped /org/gnome/shell/extensions/]" "$(cat "$d/extensions.dconf")"
  assert_eq $'dash@x\nblur@y' "$(cat "$d/enabled-extensions.txt")"
  assert_eq 3 "$(wc -l <"$d/installed-extensions.txt")"
  assert_contains "$T_OUT" "Backup complete."
}

test_a_failed_dump_keeps_the_previous_backup() {
  session
  local d="$T_ROOT/out"
  mkdir -p "$d"
  echo "[good old settings]" >"$d/desktop.dconf"
  export FAKE_DCONF=0
  t_run backup "$d"
  assert_status 1
  assert_contains "$T_OUT" "Backup incomplete — kept the previous copy of: desktop.dconf shell.dconf extensions.dconf"
  assert_eq "[good old settings]" "$(cat "$d/desktop.dconf")"
  assert_eq "" "$(find "$d" -name '*.dconf.*')" "no temp files left behind"
}

test_backup_to_the_chezmoi_target_says_how_to_keep_it() {
  session; stub chezmoi
  t_run backup
  assert_contains "$T_OUT" "chezmoi re-add $(DIR_DEFAULT)"
  t_run backup "$T_ROOT/elsewhere"
  assert_not_contains "$T_OUT" "chezmoi re-add"
}

test_backup_and_restore_need_their_tools() {
  t_minimal_path
  t_run backup
  assert_status 1
  assert_contains "$T_OUT" "missing required command: dconf"
  stub dconf
  t_run backup
  assert_contains "$T_OUT" "missing required command: gnome-extensions (part of gnome-shell)"
  t_run restore
  assert_contains "$T_OUT" "missing required command: gext"
}

test_restore_loads_present_dumps_and_enables_extensions() {
  session; stub gext '[[ $2 != blur@y ]]'
  local d="$T_ROOT/in"
  mkdir -p "$d"
  echo "[org/gnome/desktop/interface]" >"$d/desktop.dconf"
  : >"$d/shell.dconf"
  printf 'dash@x\n\nblur@y\n' >"$d/enabled-extensions.txt"
  t_run restore "$d"
  assert_status 0
  assert_called "dconf load /org/gnome/desktop/"
  assert_not_called "dconf load /org/gnome/shell/"
  assert_contains "$T_OUT" "Skipping missing/empty shell.dconf"
  assert_contains "$(cat "$T_ROOT/loaded")" "[org/gnome/desktop/interface]"
  assert_called "gext enable dash@x"
  assert_contains "$T_OUT" "warning: could not enable blur@y"
}

test_restore_finds_gext_in_local_bin_and_needs_a_backup() {
  session
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n:\n' >"$HOME/.local/bin/gext"
  chmod +x "$HOME/.local/bin/gext"
  t_run restore "$T_ROOT/none"
  assert_status 1
  assert_contains "$T_OUT" "No GNOME settings backup found: $T_ROOT/none"
}

test_a_backup_restores_into_the_same_paths() {
  session; stub gext
  backup "$T_ROOT/rt" >/dev/null 2>&1
  t_run restore "$T_ROOT/rt"
  assert_status 0
  assert_called "dconf load /org/gnome/desktop/"
  assert_called "dconf load /org/gnome/shell/"
  assert_called "dconf load /org/gnome/shell/extensions/"
  assert_called "gext enable blur@y"
}

t_main
