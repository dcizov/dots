#!/usr/bin/env bash
# Literal path handling shared by Restic and the AppImage inventory.

backup_excluded_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != *$'\n'* ]] || return 1
  # Don't follow symlinks: exclude this path in the tree, not the link's target.
  path="$(realpath -ms -- "$path")" || return 1
  [[ "$path" != / ]] || return 1
  printf '%s\n' "$path"
}

# The second argument is a normalized, non-root absolute path.
backup_path_within() {
  [[ "$1" == "$2" || "$1" == "$2/"* ]]
}

backup_literal_pattern() {
  local path="$1"
  path="${path//\\/\\\\}"
  path="${path//\[/\\[}"
  path="${path//\*/\\*}"
  path="${path//\?/\\?}"
  printf '%s\n' "$path"
}
