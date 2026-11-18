#!/usr/bin/env bash
# Manual user-side backup. Never run this from sudo or install a timer with it.
set -euo pipefail
umask 077

fail() { printf 'backup: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
usage: ucli backup preflight|init|run|snapshots|check
       ucli backup run [--dry-run] [--tag TAG]

Configure ~/.config/ucli/backup.local.bash first (or set UCLI_BACKUP_CONFIG).
Use the desktop user, not sudo. No automatic initialization or pruning.
USAGE
}

action="${1:---help}"
case "$action" in
  -h|--help) usage; exit 0 ;;
  preflight|init|run|snapshots|check) shift ;;
  *) usage >&2; exit 2 ;;
esac
restic_args=()
if [[ "$action" == run ]]; then
  restic_args=(--tag home)
  while (($#)); do
    case "$1" in
      --dry-run) restic_args+=(--dry-run) ;;
      --tag)
        (($# >= 2)) && [[ "$2" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || fail '--tag needs a name, not another flag'
        restic_args+=(--tag "$2")
        shift ;;
      *) fail "unknown option: $1" ;;
    esac
    shift
  done
else
  (($# == 0)) || fail "$action does not take extra arguments"
fi

(( EUID != 0 )) || fail 'run as the desktop user, not with sudo (see the runbook for /etc)'
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
home="$(realpath -e -- "$HOME")"
[[ "$home" != / && -d "$home" ]] || fail 'HOME is not a valid home directory'
config="${UCLI_BACKUP_CONFIG:-$HOME/.config/ucli/backup.local.bash}"
[[ -f "$config" && -r "$config" ]] || fail "set up $config using backup.local.bash.example"
BACKUP_REPO=/mnt/Data/Backup/cachyos/home
BACKUP_UUID=""
BACKUP_EXTRA_PATHS=()
BACKUP_EXCLUDE_FILE=""
# Local Bash settings, intentionally sourced only as the desktop user.
# shellcheck source=/dev/null
source "$config"
[[ "$BACKUP_UUID" =~ ^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$ ]] \
  || fail 'set BACKUP_UUID to the known ext4 filesystem UUID, not a partition ID'
[[ "$BACKUP_REPO" == /* && -d "$BACKUP_REPO" ]] || fail "repository directory is missing: $BACKUP_REPO (is the drive mounted?)"

# Hold the directory as cwd so the disk cannot be normally unmounted mid-run.
# Verify the filesystem at the *repository*, not just an ancestor directory.
cd -P -- "$BACKUP_REPO"
repo="$PWD"
[[ "$repo" == "${BACKUP_REPO%/}" ]] || fail 'BACKUP_REPO must be a canonical path without symlinks'
mount="$(findmnt -nro TARGET --target .)" || fail 'cannot identify the repository mount'
fstype="$(findmnt -nro FSTYPE --target .)" || fail 'cannot identify the repository filesystem'
uuid="$(findmnt -nro UUID --target .)" || fail 'cannot identify the repository UUID'
[[ -n "$mount" && "$mount" != / && "$fstype" == ext4 && "${uuid,,}" == "${BACKUP_UUID,,}" ]] \
  || fail "expected ext4 UUID $BACKUP_UUID at $repo; found mount=${mount:-none} type=${fstype:-none} UUID=${uuid:-none}. No backup written."
repo_mode="$(stat -c %a -- .)"
[[ -O . && -w . ]] && (( (8#$repo_mode & 077) == 0 )) \
  || fail "the repository directory must belong to you and be private (0700): $repo"

validate_source() {
  local source="$1" source_uuid
  [[ "$source" != / && "$repo/" != "$source/"* && "$source/" != "$repo/"* ]] \
    || fail "source overlaps the repository: $source"
  source_uuid="$(findmnt -nro UUID --target "$source")" || fail "cannot identify filesystem for $source"
  [[ "${source_uuid,,}" != "${uuid,,}" ]] \
    || fail "source is on the backup filesystem: $source (use a different drive for that data)"
}
validate_source "$home"
extra=()
for path in "${BACKUP_EXTRA_PATHS[@]}"; do
  [[ "$path" == /* ]] || fail "extra sources must have absolute paths: $path"
  resolved="$(realpath -e -- "$path")" || fail "extra source does not exist: $path"
  validate_source "$resolved"
  extra+=("$resolved")
done

if [[ "$action" == preflight ]]; then
  printf 'Verified ext4 mount %s (UUID %s)\nRepository: %s\nSources:\n' "$mount" "$uuid" "$repo"
  printf '  %s\n' "$home" "${extra[@]}"
  if [[ -f config && ! -L config ]]; then
    printf 'Repository config exists.\n'
  else
    printf 'No repository config yet. Initialize only if this directory is intentionally empty.\n'
  fi
  exit 0
fi

command -v restic >/dev/null || fail 'install Restic before running this command'
unset RESTIC_REPOSITORY RESTIC_REPOSITORY_FILE  # only use the verified directory

# Use an interactive password by default. If using an absolute private file,
# exclude its actual path (escape any Restic glob characters) from the archive.
if [[ -n "${RESTIC_PASSWORD_FILE:-}" ]]; then
  [[ "$RESTIC_PASSWORD_FILE" == /* && -f "$RESTIC_PASSWORD_FILE" && -r "$RESTIC_PASSWORD_FILE" ]] \
    || fail 'RESTIC_PASSWORD_FILE must name an absolute, readable password file'
  password_path="$(realpath -e -- "$RESTIC_PASSWORD_FILE")"
  mode="$(stat -c %a -- "$password_path")"
  (( (8#$mode & 077) == 0 )) || fail 'RESTIC_PASSWORD_FILE must not be accessible to group or other users'
  pattern="${password_path//\\/\\\\}"
  pattern="${pattern//\[/\\[}"
  pattern="${pattern//\*/\\*}"
  pattern="${pattern//\?/\\?}"
  for path in "${extra[@]}"; do
    [[ "$path" != "$password_path" ]] || fail 'do not list the password file as an extra source'
  done
  restic_args+=(--exclude "$pattern")
fi

if [[ "$action" == init ]]; then
  shopt -s nullglob dotglob
  entries=(*)
  ((${#entries[@]} == 0)) || fail 'init requires an empty directory; use the existing repository if already initialized'
  exec restic --repo . init
fi
[[ -f config && ! -L config ]] || fail 'no initialized Restic repository here; verify the mount and run the explicit init once'
if [[ "$action" != run ]]; then
  exec restic --repo . "$action"
fi

inventory="$script_dir/../inventory/inventory.sh"
excludes="$home/.config/restic/excludes"
if [[ -x "$script_dir/../inventory/executable_inventory.sh" ]]; then
  # Before the first chezmoi apply, use the new inventory and excludes from the
  # checkout rather than depending on what was installed in the unmodified home.
  inventory="$script_dir/../inventory/executable_inventory.sh"
  excludes="$script_dir/../../../../../private_dot_config/restic/excludes"
fi
[[ -r "$excludes" ]] || fail "cannot read the default excludes: $excludes"
restic_args+=(--exclude-file "$excludes")
if [[ -n "$BACKUP_EXCLUDE_FILE" ]]; then
  [[ "$BACKUP_EXCLUDE_FILE" == /* && -f "$BACKUP_EXCLUDE_FILE" && -r "$BACKUP_EXCLUDE_FILE" ]] \
    || fail "BACKUP_EXCLUDE_FILE must be an absolute readable file: $BACKUP_EXCLUDE_FILE"
  restic_args+=(--exclude-file "$BACKUP_EXCLUDE_FILE")
fi

state="$home/.local/state/ucli/backup"
[[ "$(realpath -m -- "$state")" == "$state" ]] || fail "inventory state directory must not use symlinks: $state"
state_parent="$state"
while [[ ! -e "$state_parent" ]]; do state_parent="${state_parent%/*}"; done
validate_source "$state_parent"
mkdir -p -- "$state"
exec {lock_fd}>>"$state/lock"
flock -n "$lock_fd" || fail 'another home backup is running'
stage="$(mktemp -d -- "$state/.run.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
image_args=()
for path in "${extra[@]}"; do image_args+=(--appimage "$path"); done
"$inventory" "$stage/manifest" "${image_args[@]}" >/dev/null || fail 'inventory failed; no backup attempted'
# A single stable path makes it easy to find the manifest in any snapshot.
manifest="$state/inventory.tar"
tar -C "$stage/manifest" -cf "$stage/inventory.tar" .
mv -T -- "$stage/inventory.tar" "$manifest"
rm -rf -- "$stage"
trap - EXIT

# --one-file-system keeps unrelated nested mounts out. Explicitly selected
# extra paths and the current manifest are still included as separate roots.
# Preserve Restic's status (including 3 for a partial backup) for the caller.
export HOME="$home"
exec restic --repo . backup --one-file-system "${restic_args[@]}" -- "$home" "$manifest" "${extra[@]}"
