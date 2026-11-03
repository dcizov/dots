# Set up snapshots and boot entries. Skips CachyOS.
[group('System')]
setup-snapshots:
    # create Btrfs subvolume, configure snapper, limine-snapper-sync
    @sudo ~/.config/ucli/scripts/system/executable_arch-snapper-limine.sh

# System menu.
[group('System')]
system:
    #!/usr/bin/env bash
    set -euo pipefail
    items=(
      'check|Show system status'
      'snapshots-dry-run|Dry-run snapshot setup'
      'detect|Show detected system facts'
      'paths|Print config paths'
      'validate-all|Validate all package arrays'
      'logs-this-boot|Show journal from this boot'
      'logs-last-boot|Show journal from last boot'
    )
    if command -v fzf >/dev/null 2>&1; then
      choice="$(printf '%s\n' "${items[@]}" | fzf --prompt='system>' --with-nth=1,2 --delimiter='|')" || exit 0
      choice="${choice%%|*}"
    else
      select item in "${items[@]}"; do choice="${item%%|*}"; break; done
    fi
    case "$choice" in
      check) ~/.config/ucli/scripts/system/executable_system-check.sh ;;
      snapshots-dry-run) sudo ~/.config/ucli/scripts/system/executable_arch-snapper-limine.sh --dry-run ;;
      detect) just --justfile "$HOME/.config/ucli/justfile" --working-directory "$HOME" profile ;;
      paths) just --justfile "$HOME/.config/ucli/justfile" --working-directory "$HOME" _paths ;;
      validate-all) ~/.config/ucli/scripts/install/executable_validate-packages.sh --all ;;
      logs-this-boot) journalctl --no-hostname -b 0 ;;
      logs-last-boot) journalctl --no-hostname -b -1 ;;
    esac

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
