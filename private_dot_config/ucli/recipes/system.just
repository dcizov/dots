# Set up snapshots and boot entries. Skips CachyOS.
[group('System')]
setup-snapshots *ARGS:
    # create Btrfs subvolume, configure snapper, limine-snapper-sync, snapshot #1
    # --no-snapshot: configure only, take no snapshot
    @sudo ~/.local/share/ucli/scripts/system/arch-snapper-limine.sh {{ARGS}}

# Rank the fastest pacman mirrors and write them to /etc/pacman.d — the Arch
# equivalent of `ujust`-style mirror tuning, ported from CachyOS'
# cachyos-rate-mirrors.
#
#   engine   rate-mirrors from [extra] (no AUR), reflector as the fallback
#   repos    arch always; cachyos-mirrorlist too when this is a CachyOS install
#   writes   /etc/pacman.d/mirrorlist, previous file kept as mirrorlist.bak
#   safety   Snapper snapshot first when snapper is configured, and nothing is
#            written without a confirmation (--yes for non-interactive)
#
#   ucli mirrors                 rank, show the top mirrors, ask, write
#   ucli mirrors --dry-run       rank and show only
#   ucli mirrors --country DE    skip the geoip lookup (--no-geo: no lookup at all)
#
# Rank pacman mirrors and install the ranking.
[group('System')]
mirrors *ARGS:
    # rate-mirrors over /etc/pacman.d/mirrorlist (+ cachyos-mirrorlist), with a backup
    @~/.local/share/ucli/scripts/system/rate-mirrors.sh {{ARGS}}

# System menu. Use `ucli --choose` to pick a system recipe interactively.
[group('System')]
system:
    # show system status
    @~/.local/share/ucli/scripts/system/system-check.sh

# Show system status.
_check:
    @~/.local/share/ucli/scripts/system/system-check.sh

# Dry-run snapshot setup.
_snapshots-dry-run:
    sudo ~/.local/share/ucli/scripts/system/arch-snapper-limine.sh --dry-run

# Show or hide the login banner (fastfetch). on = login shells, always = every shell.
[group('System')]
motd mode="status":
    #!/usr/bin/env bash
    set -euo pipefail
    state="${XDG_STATE_HOME:-$HOME/.local/state}/ucli"
    flag="$state/motd"
    case "{{mode}}" in
    on|login)
    mkdir -p "$state"
    printf 'on\n' >"$flag"
    echo "motd: on — login shells only (TTY, SSH, zsh -l)"
    ;;
    always|all)
    mkdir -p "$state"
    printf 'always\n' >"$flag"
    echo "motd: always — every interactive shell"
    ;;
    off|no)
    mkdir -p "$state"
    printf 'off\n' >"$flag"
    echo "motd: off"
    ;;
    status)
    printf 'motd: %s\n' "$(cat "$flag" 2>/dev/null || echo 'on (default, login shells)')"
    ;;
    *)
    echo "usage: ucli motd [on|always|off|status]" >&2
    exit 2
    ;;
    esac

# Fingerprint reader: install fprintd, then enroll from the desktop's own
# Settings page — GNOME (Settings → System → Users → Fingerprint Login) and
# Plasma 6 (System Settings → Users → Fingerprint) both drive fprintd directly,
# so nothing here does the enrollment for you unless you ask for `--enroll`.
# --pam additionally wires pam_fprintd into /etc/pam.d/system-auth (login,
# screen unlock, sudo); it is opt-in because PAM is the one thing in this repo
# that can keep you out, and it leaves a backup.
# Set up the fingerprint reader for the desktop's Settings UI.
[group('System')]
fingerprint *ARGS:
    # ucli fingerprint            •   --status  •   --enroll  •   --pam
    @~/.local/share/ucli/scripts/install/install-fingerprint.sh {{ARGS}}

# Create a named Snapper snapshot (needs `ucli setup-snapshots` first).
#   ucli snapshot                       "Fresh Arch Linux Installation"
#   ucli snapshot "before the upgrade"  your own description
#   ucli snapshot --dry-run             show what would happen
# Same script every other step calls, so a snapshot taken here and one taken by
# setup-desktop/setup-snapshots cannot drift apart.
[group('System')]
snapshot *ARGS:
    # create a snapper snapshot (description and flags pass straight through)
    @sudo ~/.local/share/ucli/scripts/system/snapshot-fresh-install.sh {{ARGS}}

# Internal fresh-install snapshot helper. setup-snapshots calls this in its script.
_fresh-snapshot:
    @sudo ~/.local/share/ucli/scripts/system/snapshot-fresh-install.sh

# Install a desktop environment and snapshot afterwards.
# Usage: just setup-desktop                    (full DE set, prompts for gnome/hyprland/kde)
#        sudo setup-desktop.sh --choose gnome  (interactive: pick package groups first)
# For Arch minimal: run after chezmoi apply, before ucli devmode/apps.
[group('System')]
setup-desktop *ARGS:
    # install desktop environment (gnome/hyprland/kde) + create snapshot
    @sudo ~/.local/share/ucli/scripts/install/setup-desktop.sh {{ARGS}}

# Review installed desktop packages and remove bloat.
# Usage: just debloat-desktop           (prompts for gnome/hyprland/kde)
# Run after setup-desktop to remove packages you don't need.
[group('System')]
debloat-desktop *ARGS:
    # remove DE packages you don't need (--no-snapshot skips the restore point)
    @sudo ~/.local/share/ucli/scripts/install/debloat-desktop.sh {{ARGS}}

# Backup GNOME Shell settings and extensions.
# Usage: just backup-gnome-settings
# Backs up dconf settings + enabled extensions list to ~/.local/share/ucli/settings/gnome/
[group('System')]
backup-gnome-settings:
    # backup dconf settings + enabled extensions to ~/.local/share/ucli/settings/gnome/
    @~/.local/share/ucli/scripts/install/backup-gnome-settings.sh

# Restore GNOME Shell settings and extensions from backup.
# Usage: just restore-gnome-settings
# Restores dconf settings + re-enables extensions from ~/.local/share/ucli/settings/gnome/
[group('System')]
restore-gnome-settings:
    # restore dconf settings + re-enable extensions
    @~/.local/share/ucli/scripts/install/restore-gnome-settings.sh

# Validate all package arrays.
_validate-all:
    @~/.local/share/ucli/scripts/install/validate-packages.sh --all

# Show journal from this boot.
_logs-this-boot:
    journalctl --no-hostname -b 0

# Show journal from last boot.
_logs-last-boot:
    journalctl --no-hostname -b -1
