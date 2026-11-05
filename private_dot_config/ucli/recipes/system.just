# Set up snapshots and boot entries. Skips CachyOS.
[group('System')]
setup-snapshots *ARGS:
    # create Btrfs subvolume, configure snapper, limine-snapper-sync, snapshot #1
    # --no-snapshot: configure only, take no snapshot
    @sudo ~/.local/share/ucli/scripts/system/arch-snapper-limine.sh {{ARGS}}

# Quiet boot: plymouth + this machine's kernel parameters, appended to limine.
#
#   ucli setup-boot               install/configure plymouth and add what is missing
#   ucli setup-boot --dry-run     show every change, write nothing
#   ucli setup-boot --no-plymouth kernel parameters only (no splash)
#   ucli setup-boot --force       rebuild the initramfs even when nothing changed
#
# Parameters come from KERNEL_CMDLINE_EXTRA in packages.bash (quiet splash
# loglevel=3 nowatchdog zswap.enabled=0 — the CachyOS defaults) and are *appended*
# to whatever the bootloader already has: /etc/default/limine when
# limine-mkinitcpio-hook is in charge, the cmdline: lines inside limine.conf on an
# archinstall limine, /etc/kernel/cmdline for a Unified Kernel Image. Nothing is
# replaced or removed, and the plymouth hook is put where ArchWiki wants it (after
# systemd, before sd-encrypt/encrypt). GRUB and systemd-boot are refused on
# purpose: this repo sets up limine.
[group('System')]
setup-boot *ARGS:
    # plymouth + kernel parameters appended to limine (quiet boot)
    @sudo ~/.local/share/ucli/scripts/system/setup-boot.sh {{ARGS}}

# pacman's own output: `Color` and `ILoveCandy`, uncommented in /etc/pacman.conf.
# Both are stock comments nobody ever removes. This uncomments them inside
# [options] (the only section pacman accepts them in), keeps a timestamped backup
# of the file, and validates the result with `pacman-conf --config` before it
# replaces the original — an unparsable pacman.conf would break every later
# install. Idempotent: a second run reports "already set".
#
#   ucli setup-pacman               apply
#   ucli setup-pacman --dry-run     print the diff, write nothing
#   ucli setup-pacman --status      report the two lines, write nothing
#
# Runs inside `ucli setup-system` too, right after the base packages.
[group('System')]
setup-pacman *ARGS:
    # Color + ILoveCandy in /etc/pacman.conf (backup, pacman-conf validated)
    @sudo ~/.local/share/ucli/scripts/system/setup-pacman.sh {{ARGS}}

# Write Firefox's policy file from ~/.config/ucli/firefox/extensions.txt (+ your
# personal-extensions.txt, + dev-extensions.txt with --dev), so the extensions are
# installed and enabled on the next start without a profile and without clicking.
#
#   ucli firefox-policies            apply the lists
#   ucli firefox-policies --dev      include the dev list
#   ucli firefox-policies --dry-run  print the policy, write nothing
#
# `ucli apps` and `ucli devmode` call this themselves; the recipe is for repairs.
# Check the result in about:policies.
[group('System')]
firefox-policies *ARGS:
    # extensions.txt + personal-extensions.txt -> /etc/firefox/policies/policies.json
    @sudo ~/.local/share/ucli/scripts/install/install-firefox-policies.sh {{ARGS}}

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

# Show OS, CPU, disk and firmware facts — the quick "where am I" dump.
[group('System')]
system:
    # show system status
    @~/.local/share/ucli/scripts/system/system-check.sh



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
# Take a snapshot now, with an optional description.
[group('System')]
snapshot *ARGS:
    # create a snapper snapshot (description and flags pass straight through)
    @sudo ~/.local/share/ucli/scripts/system/snapshot-fresh-install.sh {{ARGS}}


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
