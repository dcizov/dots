# CachyOS KDE backup and recovery plan

**Use Restic on `/mnt/Data/Backup` as it is.** The [CachyOS forum guide](https://discuss.cachyos.org/t/backing-up-and-restoring-cachyos-guide/32544) has the right scope: home, system configuration, and an installed-package list. Its `btrbk` send/receive example needs a Btrfs destination; [Restic](https://restic.readthedocs.io/en/stable/040_backup.html) stores encrypted, versioned, deduplicated file backups on ext4. No reformatting is needed. If Snapper is already configured on the system disk, keep it for local rollback; don't assume its root snapshots include home or survive a disk failure.

This is a **reinstall-and-restore** plan, not a bootable disk image. Save the current machine once before changing any live dotfiles, then adapt the repo before enabling recurring backups. The [manual runbook](backup.md) shows how to use the implemented inventory and home backup, back up `/etc` separately, and test a restore before applying anything.

## 1. Verify the drive and take a baseline

Run on the CachyOS PC, not in the repo sandbox:

```sh
lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS
findmnt -T / -o TARGET,SOURCE,FSTYPE
findmnt -T "$HOME" -o TARGET,SOURCE,FSTYPE
findmnt --mountpoint /mnt/Data -o TARGET,SOURCE,FSTYPE,UUID
/usr/bin/df -h -- "$HOME" /mnt/Data
du -shx -- "$HOME"
```

Check the actual mount point (`/mnt/Data`), not the `Backup` subdirectory, which may not exist yet. Stop if there is no matching mount or it isn't the expected **separate ext4 drive**. Note its filesystem UUID and check available space for the first copy plus history. The runbook checks the mount and UUID before creating `Backup`. `/usr/bin/df` bypasses the `duf` alias. A `du -x` total doesn't cover other filesystems or unreadable data.

Use two Restic repositories under `/mnt/Data/Backup/cachyos/`: `home` owned by your desktop user, and `system` owned by root. This keeps the home job unprivileged while allowing the system job to read protected `/etc` files. Initialize them manually only after checking the mount. Keep repository passwords and recovery instructions available independently of this PC and the repositories. Don't commit passwords, unredacted manifests, or private app data to Git.

Close browsers, mail, and other apps that write databases; stop or export any VM or service data you intend to include. If [rootless Podman storage](backup.md#rootless-podman-storage) is unreadable, preserve and verify any unique data before opting out of the raw store. The home backup helper creates and includes a fresh private inventory. Take the home and system backups manually and verify them before applying any dotfile changes.

## 2. Define what will be restored

| Area | What to save | What to rebuild or review |
| --- | --- | --- |
| Home and Plasma | Your entire home, including hidden files, `~/.config`, `~/.local/share`, `~/.local/state`, browser profiles, local Git work, SSH/GPG keys, and the KDE wallet. Spot-check `kdeglobals`, `kwinrc`, shortcuts, Plasma's `plasma-org.kde.plasma.desktop-appletsrc`, and any custom themes, widgets, and wallpapers. | Exclude only clearly regenerable cache/trash, snapshot trees, and reviewed paths. Locate important data on nested mounts or behind symlinks and list it explicitly; backing up a symlink does not save the target. |
| Pacman and AUR | `pacman -Qqen` for explicit repo-backed packages, `pacman -Qqem` for explicit foreign packages, `pacman -Q` for all installed versions, and `pacman -Qm` to catch foreign dependencies. Record `pacman-conf --repo-list`. Preserve custom PKGBUILDs, patches, and built `*.pkg.tar.*` files for local or hard-to-rebuild packages. | Foreign means “not in the configured repositories,” not necessarily AUR. Reinstall reviewed repo packages first; then rebuild verified AUR packages as your user with Shelly or paru, and reinstall local artifacts where needed. Do not restore an old pacman database or copy `/usr` onto the new system. |
| Flatpak | Full app refs (ID/arch/branch), origin, and remote names/URLs **by installation** (`--user`, `--system`, or a named installation). Preserve `~/.var/app` for settings/data and the actual per-app and global override files: `${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/overrides` and `/var/lib/flatpak/overrides` for the default system install. Include any data Flatpaks write outside the sandbox. | Re-add trusted remotes with their normal verification, install refs into their original scopes, and review overrides. Re-download runtimes and app payloads by default; keep overrides when excluding the regenerable Flatpak store. |
| AppImages | The actual binaries with executable permissions, SHA-256 checksums, any sibling `Name.AppImage.home` or `Name.AppImage.config` directories, and desktop launchers/icons (typically under `~/.local/share/applications` and `~/.local/share/icons`). Check `~/Applications`, `~/.local/bin`, and any locations outside home, such as `/opt` or another drive. | Restore the binary and its settings together. Confirm its hash and adjust launcher paths if they moved. An inventory alone cannot recreate an AppImage that is no longer downloadable. |
| System configuration and data | Back up `/etc` as root, plus the system Flatpak overrides and any explicitly selected paths outside home: for example `/usr/local`, `/opt` AppImages, or VM images and database exports if used. Record custom services you need to re-enable. | Restore by comparing with the fresh installation. Never replace all of `/etc` or blindly copy `fstab`, `crypttab`, account databases, or boot files. Use native database dumps or shut down services for consistent data, including the dev database volumes if you use them. |

Version lists document what was installed; they do **not** guarantee the same versions can be downloaded later. If offline or exact-version recovery is required, also preserve a compatible set of package artifacts and dependencies plus Flatpak apps and runtimes. Files already located on the `/mnt/Data` drive need a backup on a **different** device or service to survive that drive failing.

## 3. Adapt chezmoi for the existing CachyOS install

1. Reuse the [existing CachyOS path](distros.md) and detection in `scripts/lib/detect.sh`. When deployed, `ucli profile` shows the detected and configured values. Use a local profile with `machine = "workstation"`, `desktop = "kde"`, and role/gaming set to your needs. Keep your current terminal (e.g. Konsole); no need to install another one just for the backup. Leave the working kernel, NVIDIA drivers, bootloader, and CachyOS repositories alone. Do not run the fresh-install `ucli setup-system` on this working machine to adapt dotfiles.
2. Audit desktop-specific hooks before applying. `run_onchange_after_96-desktop-palette.sh` now requires an actual GNOME session, so Plasma skips it even with `gsettings` and a session bus. Keep GNOME defaults and extension installs out of the KDE path.
3. Keep portable, intentional settings in chezmoi. Keep the local `chezmoi.toml`, `packages.local.bash`, and `local.zsh` in the encrypted backup; use the package overlay for deliberate machine-specific choices, not as a dump of the full inventory. Leave KDE's live desktop state, browser profiles, wallets, and app data to Restic rather than importing all of `~/.config` into Git.
4. Run the repo's offline checks and review `chezmoi diff` and `chezmoi apply --dry-run --verbose --exclude=scripts` as your user. Review scripts separately; apply only reviewed files first. Confirm Plasma, the shell, and the apps still work before running any optional package recipes.

## 4. Automate only after a restore test

- The inventory records scoped Flatpak refs/remotes and collects paths/checksums for the configured non-home AppImage locations. It distinguishes an empty pacman query from errors and writes a fresh private manifest with each home backup. Per-app override files are backed up separately from the scoped global reports.
- Review the narrow [`restic/excludes`](../private_dot_config/restic/excludes) for your machine. The helper uses `--one-file-system`, so list every intended nested mount/subvolume explicitly. Check what was actually included with `restic ls`.
- Enable opt-in daily systemd timers with `Persistent=true` after the manual run and restore pass. Use an unprivileged home job and a separately installed, root-owned system job that never executes or sources user-writable repo code. Keep unattended credentials in protected files or systemd credentials, not in Git or unit contents. On **every** run verify the actual mount and expected ext4 UUID and refuse to run if the mount or initialized repository is missing. A test with the drive unmounted must fail visibly and write nothing to the system disk at the backup path. Report errors, including partial backups, rather than treating a snapshot ID as success.
- Start with **7 daily, 4 weekly, and 6 monthly** snapshots per repo; adjust for available space. Preview deletion with `restic forget --dry-run`; keep the pre-change baseline until the migration and its restore are verified. Run `restic check` regularly and periodically verify data with `--read-data` or rotating `--read-data-subset` checks. Add a second encrypted copy on a disconnected USB drive or an off-site repository: an always-connected drive in the same PC does not protect against theft, power damage, or malware.

## 5. Prove you can recover

First restore selected files from both repositories into **empty staging directories**, never over the running system. Check a document, a Plasma config, a Flatpak settings file and its override, a system config, and an AppImage (mode and checksum). Check that the manifests are readable. If possible, rehearse reinstalling one repo package, one AUR app, one Flatpak with its restored data, and launching the AppImage on a test install.

For a disk failure: reinstall CachyOS with Plasma without formatting the backup drive; recreate the user (same ownership or explicitly remap it), mount the backup drive, and restore to staging. Install reviewed repo packages, AUR/local packages, and Flatpaks from the inventories. Merge needed system config into the fresh `/etc`. Restore home/app data with Plasma logged out and apps closed, adjust AppImage paths if needed, then review and apply the chezmoi-managed files last. Confirm the Plasma layout, apps, and important files before calling the recovery complete.
