#!/usr/bin/env bash
# The five repairs behind `ucli fix` and their dispatcher. UCLI_TEST_ROOT skips
# the root check and roots /var and /usr/share in the sandbox; pacman,
# pacman-key, paccache, journalctl, fuser and pgrep are stubs.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

fix()      { ( source ../private_dot_local/share/ucli/scripts/fix/executable_fix.sh "$@" ); }
cache()    { ( source ../private_dot_local/share/ucli/scripts/fix/executable_fix-cache.sh "$@" ); }
keyrings() { ( source ../private_dot_local/share/ucli/scripts/fix/executable_fix-keyrings.sh "$@" ); }
lock()     { ( source ../private_dot_local/share/ucli/scripts/fix/executable_fix-lock.sh "$@" ); }
native()   { ( source ../private_dot_local/share/ucli/scripts/fix/executable_fix-native.sh "$@" ); }
orphans()  { ( source ../private_dot_local/share/ucli/scripts/fix/executable_fix-orphans.sh "$@" ); }

root() {
  t_minimal_path
  export UCLI_TEST_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_TEST_ROOT/var/lib/pacman" "$UCLI_TEST_ROOT/var/cache/pacman/pkg"
  stub du 'echo "512	$2"'
  stub journalctl '[[ $1 == --disk-usage ]] && echo "Archived and active journals take up 1.2G in the file system."; exit 0'
}

# --- dispatcher --------------------------------------------------------------

test_fix_without_an_action_prints_the_table() {
  t_run fix
  assert_status 0
  assert_contains "$T_OUT" "keyrings   refresh pacman's keyring"
  assert_contains "$T_OUT" "Every action takes --dry-run."
}

test_fix_rejects_an_unknown_action() {
  t_run fix teleport
  assert_status 2
  assert_contains "$T_OUT" "unknown fix action: teleport"
}

test_fix_routes_to_the_action_script_with_its_flags() {
  # deployed names: fix.sh next to fix-<action>.sh
  local d="$T_ROOT/fix"
  mkdir -p "$d"
  cp ../private_dot_local/share/ucli/scripts/fix/executable_fix.sh "$d/fix.sh"
  printf '#!/usr/bin/env bash\necho "lock got: $*"\n' >"$d/fix-lock.sh"
  chmod +x "$d/fix.sh" "$d/fix-lock.sh"
  t_run "$d/fix.sh" lock --dry-run
  assert_status 0
  assert_eq "lock got: --dry-run" "$T_OUT"
}

test_every_action_refuses_to_run_unprivileged() {
  ((EUID != 0)) || return 0
  local a
  for a in cache keyrings lock native orphans; do
    t_run "$a"
    assert_status 1
    assert_contains "$T_OUT" "Run as root: sudo ucli fix $a"
  done
}

test_every_action_has_help_and_rejects_unknown_options() {
  local a
  for a in cache keyrings lock native orphans; do
    t_run "$a" --help
    assert_status 0
    assert_contains "$T_OUT" "sudo ucli fix $a"
    t_run "$a" --bogus
    assert_status 2
  done
}

# --- cache -------------------------------------------------------------------

test_cache_uses_paccache_with_the_requested_keep() {
  root; stub paccache; stub pacman
  t_run cache --keep 1
  assert_status 0
  assert_called "paccache -rk1"
  assert_called "paccache -ruk0"
  assert_called "journalctl --vacuum-size=200M"
  assert_not_called "pacman -Sc"
  assert_contains "$T_OUT" "package cache: 512 MB → 512 MB"
}

test_cache_falls_back_to_pacman_Sc_without_paccache() {
  root; stub pacman
  t_run cache
  assert_called "pacman -Sc --noconfirm"
  assert_contains "$T_OUT" "paccache not found (pacman-contrib)"
}

test_cache_dry_run_changes_nothing() {
  root; stub paccache; stub pacman
  t_run cache --dry-run
  assert_status 0
  assert_contains "$T_OUT" "+ paccache -rk2"
  assert_contains "$T_OUT" "+ journalctl --vacuum-size=200M"
  assert_not_called "paccache"
  assert_not_called "journalctl --vacuum"
}

test_cache_keep_must_be_a_number() {
  root
  t_run cache --keep many
  assert_status 2
  assert_contains "$T_OUT" "--keep takes a number"
  t_run cache --keep
  assert_status 2
}

# --- keyrings ----------------------------------------------------------------

keyring_files() {
  mkdir -p "$UCLI_TEST_ROOT/usr/share/pacman/keyrings"
  local k; for k in "$@"; do : >"$UCLI_TEST_ROOT/usr/share/pacman/keyrings/$k.gpg"; done
}

test_keyrings_refresh_is_the_gentle_default() {
  root; keyring_files archlinux
  stub pacman-key '[[ $1 == --list-keys ]] && printf "pub x\npub y\n"; exit 0'
  t_run keyrings
  assert_status 0
  assert_called "pacman-key --refresh-keys"
  assert_not_called "pacman-key --init"
  assert_contains "$T_OUT" "public keys: 2"
}

test_keyrings_a_failed_refresh_repopulates_every_present_keyring() {
  root; keyring_files archlinux cachyos
  stub pacman-key '[[ $1 == --refresh-keys ]] && exit 1; exit 0'
  t_run keyrings
  assert_status 0
  assert_contains "$T_OUT" "keyrings available: archlinux cachyos"
  assert_contains "$T_OUT" "refresh failed"
  assert_called "pacman-key --init"
  assert_called "pacman-key --populate archlinux"
  assert_called "pacman-key --populate cachyos"
}

test_keyrings_reset_dry_run_prints_the_sequence() {
  root
  stub pacman-key
  t_run keyrings --reset --dry-run
  assert_status 0
  assert_contains "$T_OUT" "+ pacman-key --init"
  assert_contains "$T_OUT" "+ pacman-key --populate archlinux"
  assert_contains "$T_OUT" "+ pacman-key --refresh-keys"
  assert_not_called "pacman-key"
}

# --- lock --------------------------------------------------------------------

test_lock_without_a_lock_file_is_a_no_op() {
  root
  t_run lock
  assert_status 0
  assert_contains "$T_OUT" "is not there — nothing to do"
}

test_lock_a_stale_lock_is_removed() {
  root; stub pgrep 'exit 1'; stub fuser 'exit 1'
  : >"$UCLI_TEST_ROOT/var/lib/pacman/db.lck"
  t_run lock --dry-run
  assert_contains "$T_OUT" "+ rm -f"
  assert_file "$UCLI_TEST_ROOT/var/lib/pacman/db.lck"
  t_run lock
  assert_status 0
  assert_no_file "$UCLI_TEST_ROOT/var/lib/pacman/db.lck"
}

test_lock_an_open_handle_or_running_pacman_keeps_the_lock() {
  root; stub pgrep 'exit 1'; stub fuser 'exit 0'
  : >"$UCLI_TEST_ROOT/var/lib/pacman/db.lck"
  t_run lock
  assert_status 1
  assert_contains "$T_OUT" "something has the file open"
  stub fuser 'exit 1'; stub pgrep '[[ $2 == paru ]]'
  t_run lock
  assert_status 1
  assert_contains "$T_OUT" "paru is running"
  assert_file "$UCLI_TEST_ROOT/var/lib/pacman/db.lck"
}

# --- native ------------------------------------------------------------------

native_world() {
  root
  stub pacman 'case "$1" in
    -Qnq) printf "bash\nglibc\nold-dropped\n" ;;
    -Si)  [[ $2 != old-dropped ]] ;;
    -S)   cat >"${T_CALLS%/*}/reinstalled" ;;
  esac'
}

test_native_list_counts_and_skips_dropped_packages() {
  native_world
  t_run native --list
  assert_status 0
  assert_contains "$T_OUT" "native:      3"
  assert_contains "$T_OUT" "in repos:    2"
  assert_contains "$T_OUT" "skipped:     1 (dropped from the repos)"
  assert_contains "$T_OUT" "first 20:    bash glibc"
}

test_native_feeds_the_package_names_on_stdin() {
  native_world
  t_run native --yes
  assert_status 0
  assert_called "pacman -S --needed --noconfirm -"
  assert_eq $'bash\nglibc' "$(cat "$T_ROOT/reinstalled")"
}

test_native_dry_run_and_an_unreadable_database() {
  native_world
  t_run native --dry-run
  assert_contains "$T_OUT" "<2 package names> | sudo pacman -S --needed --noconfirm -"
  assert_not_called "pacman -S "
  stub pacman 'exit 1'
  t_run native
  assert_status 1
  assert_contains "$T_OUT" "no native packages found"
}

# --- orphans -----------------------------------------------------------------

test_orphans_none_is_reported() {
  root; stub pacman 'exit 1'
  t_run orphans --yes
  assert_status 0
  assert_contains "$T_OUT" "none — every installed dependency is still required"
}

test_orphans_are_removed_in_one_transaction() {
  root; stub pacman '[[ $1 == -Qtdq ]] && printf "libfoo\npython-bar\n"; exit 0'
  t_run orphans --dry-run
  assert_contains "$T_OUT" "+ pacman -Rns --noconfirm libfoo python-bar"
  assert_not_called "pacman -Rns"
  t_run orphans --yes
  assert_status 0
  assert_called "pacman -Rns --noconfirm libfoo python-bar"
  assert_contains "$T_OUT" "removed 2 orphan(s)"
}

t_main
