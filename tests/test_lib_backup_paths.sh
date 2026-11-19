#!/usr/bin/env bash
# lib/backup-paths.sh: exclusions are normalised absolute paths (never /),
# containment is by path component, and restic patterns are literal.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

paths() { source ../private_dot_local/share/ucli/scripts/lib/backup-paths.sh; }

test_excluded_paths_are_normalised_and_absolute() {
  paths
  assert_eq "/home/a/b" "$(backup_excluded_path /home/a/./x/../b/)"
  ! backup_excluded_path relative/dir >/dev/null || t_die "relative path accepted"
  ! backup_excluded_path / >/dev/null || t_die "/ accepted"
  ! backup_excluded_path $'/home/a\nb' >/dev/null || t_die "newline accepted"
  ln -s /etc "$T_ROOT/link"
  assert_eq "$T_ROOT/link" "$(backup_excluded_path "$T_ROOT/link")" "the link itself, not its target"
}

test_within_is_by_component() {
  paths
  backup_path_within /home/a/b /home/a || t_die "child not within"
  backup_path_within /home/a /home/a || t_die "self not within"
  ! backup_path_within /home/ab /home/a || t_die "sibling prefix counted as within"
}

test_literal_patterns_escape_glob_characters() {
  paths
  # restic matches like Go's filepath.Match: [ * ? and \ are special; a ]
  # outside a class is already literal, so it is left alone.
  assert_eq '/data/\[x]\*\?\\y' "$(backup_literal_pattern '/data/[x]*?\y')"
}

t_main
