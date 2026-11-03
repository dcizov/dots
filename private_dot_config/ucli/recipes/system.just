# Set up snapshots and boot entries. Skips CachyOS.
[group('System')]
setup-snapshots:
    # create Btrfs subvolume, configure snapper, limine-snapper-sync
    @sudo ~/.config/ucli/scripts/system/executable_arch-snapper-limine.sh

# System menu. Use `ucli --choose` to pick a system recipe interactively.
[group('System')]
system:
    # show system status
    @~/.config/ucli/scripts/system/executable_system-check.sh

# Show system status.
_check:
    @~/.config/ucli/scripts/system/executable_system-check.sh

# Dry-run snapshot setup.
_snapshots-dry-run:
    sudo ~/.config/ucli/scripts/system/executable_arch-snapper-limine.sh --dry-run

# Internal fresh-install snapshot helper. setup-snapshots calls this in its script.
_fresh-snapshot:
    @sudo ~/.config/ucli/scripts/system/executable_snapshot-fresh-install.sh

# Install a desktop environment and snapshot afterwards.
# Usage: just setup-desktop                    (full DE set, prompts for gnome/hyprland/kde)
#        sudo setup-desktop.sh --choose gnome  (interactive: pick package groups first)
# For Arch minimal: run after chezmoi apply, before ucli devmode/apps.
[group('System')]
setup-desktop:
    # install desktop environment (gnome/hyprland/kde) + create snapshot
    @sudo ~/.config/ucli/scripts/install/executable_setup-desktop.sh

# Review installed desktop packages and remove bloat.
# Usage: just debloat-desktop           (prompts for gnome/hyprland/kde)
# Run after setup-desktop to remove packages you don't need.
[group('System')]
debloat-desktop:
    # remove DE packages you don't need
    @sudo ~/.config/ucli/scripts/install/executable_debloat-desktop.sh

# Backup GNOME Shell settings and extensions.
# Usage: just backup-gnome-settings
# Backs up dconf settings + enabled extensions list to ~/.config/ucli/settings/gnome/
[group('System')]
backup-gnome-settings:
    # backup dconf settings + enabled extensions to ~/.config/ucli/settings/gnome/
    @~/.config/ucli/scripts/install/executable_backup-gnome-settings.sh

# Restore GNOME Shell settings and extensions from backup.
# Usage: just restore-gnome-settings
# Restores dconf settings + re-enables extensions from ~/.config/ucli/settings/gnome/
[group('System')]
restore-gnome-settings:
    # restore dconf settings + re-enable extensions
    @~/.config/ucli/scripts/install/executable_restore-gnome-settings.sh

# Validate all package arrays.
_validate-all:
    @~/.config/ucli/scripts/install/executable_validate-packages.sh --all

# Show journal from this boot.
_logs-this-boot:
    journalctl --no-hostname -b 0

# Show journal from last boot.
_logs-last-boot:
    journalctl --no-hostname -b -1
