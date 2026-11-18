# First CachyOS backup to an ext4 drive

This is the manual workflow from the [backup plan](cachyos-backup-plan.md). It uses two encrypted Restic repositories on `/mnt/Data/Backup`: `cachyos/home` for your user and `cachyos/system` for `/etc` and selected system data. It does not set up a timer, prune snapshots, or change Plasma. A list of packages lets you reinstall them; only files actually in a snapshot can be restored directly.

## 1. Check the drive before creating anything

On the CachyOS PC, check the destination and its capacity:

```sh
lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS
findmnt -T /mnt/Data/Backup -o TARGET,SOURCE,FSTYPE,UUID
df -h "$HOME" /mnt/Data/Backup
du -shx "$HOME"
```

Verify this is your **separate ext4 drive** and note its filesystem UUID (not its partition UUID). If the target is `/`, stop: the backup path is on the root filesystem. `/mnt/Data` is a valid target if `Backup` is a subdirectory on it. Don't create anything under the destination until this check passes. If you have unique data on `/mnt/Data` itself, back it up to a different device or service.

Have `restic` available on the machine (`restic version`); it is in the repo's optional system tools. Don't start a fresh-install setup or do a partial pacman upgrade just to install it. The code below uses Bash; start `bash` first if your shell is Fish. Run the snippets in the same Bash session, starting in this copy of the dotfiles checkout.

```bash
backup=/mnt/Data/Backup
uuid='REPLACE-WITH-THE-VERIFIED-EXT4-UUID'
verify_drive() {
  local path="$1" target type actual
  target=$(findmnt -nro TARGET --target "$path") || return 1
  type=$(findmnt -nro FSTYPE --target "$path") || return 1
  actual=$(findmnt -nro UUID --target "$path") || return 1
  if [[ ! $target || $target == / || $type != ext4 || ! $actual || ${actual,,} != ${uuid,,} ]]; then
    printf 'Wrong or missing backup drive: %s\n' "$path" >&2
    return 1
  fi
}
(
  set -e
  cd -P -- "$backup"
  [[ $PWD == "$backup" ]] || { echo 'Use the actual path (not a symlink).' >&2; exit 1; }
  verify_drive .
  # First setup only: this deliberately refuses an existing cachyos directory.
  sudo mkdir -m 0755 -- cachyos
  sudo install -d -m 0700 -o "$(id -u)" -g "$(id -g)" -- cachyos/home
  sudo mkdir -m 0700 -- cachyos/system
)
```

If `cachyos` already exists, inspect it rather than changing ownership or overwriting it. Reuse only the correct repositories. Keep `cachyos` and `cachyos/system` owned by root; only `cachyos/home` belongs to your user. Do not put passwords in this checkout or in the machine config. Record the two repository passwords securely somewhere you can access without this PC.

## 2. Take the home baseline before applying dotfiles

Use the helper directly from this checkout so you can back up before deploying anything. Copy the example to a **private local** file, then edit it: set `BACKUP_UUID` to the UUID you just verified. `BACKUP_REPO` is already set to `/mnt/Data/Backup/cachyos/home` in the example. Don't change an existing machine config unnoticed.

```bash
scratch=$(mktemp -d)
export UCLI_BACKUP_CONFIG="$scratch/backup.local.bash"
install -m 0600 private_dot_config/ucli/backup.local.bash.example "$UCLI_BACKUP_CONFIG"
nano "$UCLI_BACKUP_CONFIG"

home_backup="$PWD/private_dot_local/share/ucli/scripts/backup/executable_backup-home.sh"
"$home_backup" preflight
```

Review the sources in `preflight`. Home is included by default, with dotfiles, Plasma settings, browsers, and `~/.var/app` data. Fill `BACKUP_EXTRA_PATHS` with any additional absolute paths you want to include, as long as they aren't on the backup filesystem. This includes nested mounts/subvolumes in home, anything behind a symlink that lives outside the selected source directories, and non-home AppImages. For a portable AppImage, select its directory to get its binary and any `.AppImage.home` and `.AppImage.config` siblings. Root-only data belongs in the system backup below.

```bash
# Run init once, only if preflight shows an intentionally empty home directory.
"$home_backup" init
# Test scope (no new snapshot; refreshes the local manifest).
"$home_backup" run --dry-run
# Close your browsers, mail, and other apps writing data before the real run.
"$home_backup" run --tag pre-chezmoi
"$home_backup" snapshots
"$home_backup" check
```

Stop if a step fails. The helper never creates a directory on a missing drive, never initializes during `run`, and returns Restic's exit status. **A snapshot with exit status 3 is partial**, not a successful baseline. A run includes a fresh private `~/.local/state/ucli/backup/inventory.tar`. It has pacman lists and versions (including foreign dependencies), Flatpak refs and remotes by scope, and AppImage paths and checksums. The default home excludes skip top-level cache/trash/snapshots and the standard user Flatpak app/runtime/repo payloads, but not Flatpak settings or overrides. Use `BACKUP_EXCLUDE_FILE` for extra reviewed exclusions; do not exclude whole state directories wholesale.

For just the manifest after deployment, `ucli inventory` writes a new directory in `~/system-inventory`. You can pass an unused absolute output path and one or more `--appimage /absolute/path` options. It does **not** make copies of AppImage binaries or pacman packages. If you need an unavailable AUR/local package, include its build files and a known-good package archive as data. Save custom `.flatpakrepo` files and trusted signing material if you can't retrieve them later. For an offline reinstall, preserve the needed compatible package and Flatpak payloads separately before relying on the default exclusions.

## 3. Back up system files as root, separately

Use the system repo with this Bash function. Only the explicit Restic operation and its mount check run under sudo; it does not source the user config or run code from a writable checkout as root. Use the function for each system operation so it always checks the mounted volume.

```bash
system_restic() {
  sudo -- /bin/bash -c '
    set -euo pipefail
    umask 077
    repo=$1 uuid=$2; shift 2
    cd -P -- "$repo"
    target=$(findmnt -nro TARGET --target .)
    type=$(findmnt -nro FSTYPE --target .)
    actual=$(findmnt -nro UUID --target .)
    mode=$(stat -c %a .)
    if [[ $PWD != "$repo" || ! -O . || ! $target || $target == / || $type != ext4 || ! $actual || ${actual,,} != ${uuid,,} ]] \
       || (( (8#$mode & 077) != 0 )); then
      echo "Wrong or missing system backup drive or repository permissions" >&2
      exit 1
    fi
    if [[ $1 == init ]]; then
      shopt -s dotglob nullglob
      entries=(*)
      ((${#entries[@]} == 0)) || { echo "System init requires an empty directory" >&2; exit 1; }
    else
      [[ -f config && ! -L config ]] || { echo "System repository is not initialized" >&2; exit 1; }
    fi
    unset RESTIC_REPOSITORY RESTIC_REPOSITORY_FILE RESTIC_PASSWORD RESTIC_PASSWORD_FILE RESTIC_PASSWORD_COMMAND
    exec /usr/bin/restic --repo . "$@"
  ' bash "$backup/cachyos/system" "$uuid" "$@"
}

system_restic init                          # once, if the system repo is new
system_paths=(/etc)
if [[ -d /var/lib/flatpak/overrides ]]; then
  system_paths+=(/var/lib/flatpak/overrides)
fi
# Add paths you actually use, e.g. root-owned AppImages in /opt, system Flatpak
# overrides outside the default location, and consistent database exports.
system_restic backup --one-file-system --tag pre-chezmoi -- "${system_paths[@]}"
system_restic snapshots
system_restic check
```

Review nonstandard Flatpak installation paths (`flatpak --installations` if installed). Add any actual system override directories on the source disks to `system_paths`; always exclude the backup filesystem from sources. Export database data or stop its writers before taking an application-consistent backup. Don't try to back up the running OS by adding `/`, `/proc`, `/sys`, a whole mounted backup drive, or the pacman database.

## 4. Restore a few files before applying the CachyOS profile

Use the snapshot IDs printed by the two `snapshots` commands. Choose a document, a Plasma config file, a Flatpak settings file, and a real AppImage path from `restic ls`. Restore into **new** staging directories, not into your live home or `/etc`. For example, in the Bash session above:

```bash
staging=$(mktemp -d)
(
  set -e
  cd -P -- "$backup/cachyos/home"
  [[ $PWD == "$backup/cachyos/home" ]]
  verify_drive .
  restic --repo . ls HOME_SNAPSHOT_ID
  restic --repo . restore HOME_SNAPSHOT_ID --target "$staging/home" \
    --include "$HOME/.config/kdeglobals" \
    --include "$HOME/.local/state/ucli/backup/inventory.tar"
)
system_restic restore SYSTEM_SNAPSHOT_ID --target "$staging/system" --include /etc/fstab
```

Replace the uppercase snapshot-ID placeholders and the sample paths as needed. Add `--include` for your document, Flatpak settings/override, and AppImage. Paths inside the staging directory mirror their original absolute paths. Check the restored AppImage's hash and executable bit, and inspect `inventory.tar` with `tar -tf`. A complete backup also needs any important data you can't see in this sample; check one file from each additional source.

After the restore test, save your machine-only config to `~/.config/ucli/backup.local.bash` (mode `0600`, not tracked) and `unset UCLI_BACKUP_CONFIG` when you want to use that copy. In your existing chezmoi config, set `machine = "workstation"` and `desktop = "kde"` in the existing `[data]` table if you want explicit values. Leave the terminal and role choices to your setup; applying dotfiles does not require replacing Konsole or running an installer profile.

```bash
# From a reviewed checkout; --source points at this branch, not at a remote.
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply --dry-run --verbose --exclude=scripts \
  "$HOME/.config/ucli" "$HOME/.local/share/ucli" "$HOME/.local/bin/ucli" \
  "$HOME/.config/restic/excludes"
```

If the preview is right, repeat that targeted apply without `--dry-run`. It avoids applying other dotfiles or running hooks. `ucli profile` should report CachyOS and KDE. Future manual runs can use `ucli backup preflight`, `ucli backup run`, `ucli backup snapshots`, and `ucli backup check`. Do not run the fresh-install pipeline or rebuild boot, GPU, or snapshot settings just for this backup.

For full recovery after a disk failure, follow the [restore order in the plan](cachyos-backup-plan.md#5-prove-you-can-recover). Reinstall and merge configs selectively; don't restore `fstab` over the newly installed system. Schedule backups only after this manual test. Review retention with `restic forget --dry-run --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --keep-tag pre-chezmoi` against each verified repository before deleting anything. Make a second offline or off-site copy when possible.
