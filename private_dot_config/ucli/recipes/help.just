# Show common flows.
[group('Help')]
usage:
    @printf '%s\n' 'Day to day:'
    @printf '%s\n' '  ucli update      # pacman + AUR + flatpaks + dev box'
    @printf '%s\n' '  ucli logs        # this boot / last boot / devbox / pacman'
    @printf '%s\n' '  ucli clean-system'
    @printf '%s\n' ''
    @printf '%s\n' 'Setup (Arch minimal, in order):'
    @printf '%s\n' '  ucli setup-snapshots   # snapper + limine, creates snapshot #1'
    @printf '%s\n' '  ucli snapshot [desc]   # extra snapshot; one script for all of them'
    @printf '%s\n' '  ucli setup-system gnome  # base + DE + shell + terminal/browser + extensions'
    @printf '%s\n' '  ucli debloat-desktop   # remove DE packages you do not need (optional)'
    @printf '%s\n' '  ucli setup-extensions  # GNOME only: install/enable managed extensions'
    @printf '%s\n' '  ucli cli               # + cosmetics: eza, bat, zoxide, atuin, fzf, glow'
    @printf '%s\n' '  ucli apps              # firefox + terminal + personal apps, flatpaks'
    @printf '%s\n' ''
    @printf '%s\n' 'Each step is rerunnable and also manual:'
    @printf '%s\n' '  ucli setup-desktop [gnome|kde|hyprland]  # DE only (+ snapshot)'
    @printf '%s\n' '  ucli setup-cli / setup-apps              # aliases of cli / apps'
    @printf '%s\n' ''
    @printf '%s\n' 'Snapshots: every step takes one from the same script; --no-snapshot'
    @printf '%s\n' '           (or UCLI_NO_SNAPSHOT=1) turns them all off.'
    @printf '%s\n' '  ucli devmode           # developer wizard: dev-cli + dev packages + dev box'
    @printf '%s\n' '  ucli gaming            # gaming profile'
    @printf '%s\n' '  ucli install-paru      # AUR helper (idempotent)'
    @printf '%s\n' '  ucli vscodium-extensions'
    @printf '%s\n' '  ucli chezmoi-apply     # deploy dotfiles'
    @printf '%s\n' '  ucli devbox-reconcile  # create/update dev box'
    @printf '%s\n' '  ucli devbox-create ubuntu [name]  # throwaway box from a stock image'
    @printf '%s\n' '  ucli sync              # Syncthing: folder sync between machines'
    @printf '%s\n' '  ucli config-audit      # .pacnew + locally modified package files'
    @printf '%s\n' '  ucli virt [--status]   # qemu/libvirt/virt-manager + libvirtd'
    @printf '%s\n' '  ucli ms-fonts          # AUR ttf-ms-fonts (Arial, Times New Roman, …)'
    @printf '%s\n' ''
    @printf '%s\n' 'GNOME:'
    @printf '%s\n' '  ucli gnome             # extensions, settings backup/restore'
    @printf '%s\n' '  ucli backup-gnome-settings'
    @printf '%s\n' '  ucli restore-gnome-settings'
    @printf '%s\n' ''
    @printf '%s\n' 'System:'
    @printf '%s\n' '  ucli setup-snapshots   # snapper + limine'
    @printf '%s\n' '  ucli system            # checks and maintenance helpers'
    @printf '%s\n' '  ucli mirrors           # rank pacman mirrors (rate-mirrors, keeps a .bak)'
    @printf '%s\n' '  ucli check             # offline checks: bash/zsh syntax, just, arrays'
    @printf '%s\n' '  ucli motd [on|always|off]  # login banner (fastfetch)'
    @printf '%s\n' '  ucli fingerprint       # reader in the DE Settings UI (--pam for login/sudo)'
    @printf '%s\n' ''
    @printf '%s\n' 'Maintenance:'
    @printf '%s\n' '  ucli update            # full system upgrade'
    @printf '%s\n' '  ucli clean-system      # dangling images, old cache'
    @printf '%s\n' '  ucli report            # machine facts to file'
    @printf '%s\n' '  ucli bios / bios-info  # firmware settings'
    @printf '%s\n' '  ucli changelogs        # last pacman transaction'
    @printf '%s\n' '  ucli state             # versioned gates + devmode marker'
    @printf '%s\n' ''
    @printf '%s\n' 'Inventory:'
    @printf '%s\n' '  ucli inventory         # packages, apps, settings'
    @printf '%s\n' ''
    @printf '%s\n' 'Dev box:'
    @printf '%s\n' '  ucli devbox            # menu: reconcile, shell, versions, …'
    @printf '%s\n' ''
    @printf '%s\n' 'Browse commands:'
    @printf '%s\n' '  ucli --choose'
    @printf '%s\n' ''
    @printf '%s\n' 'Direct tools:'
    @printf '%s\n' '  chezmoi diff && chezmoi apply -v'
    @printf '%s\n' '  cd ~/.config/dev-services && docker compose up -d'

# Show configured and detected profile data.
[group('Help')]
profile:
    @~/.local/share/ucli/scripts/system/detect.sh

# Check setup health: dotfiles, shell, tools, apps, gates, dev box.
[group('Help')]
doctor:
    @~/.local/share/ucli/scripts/check/doctor.sh

# Run the offline checks: bash -n, zsh -n, just parses, package arrays, shellcheck.
[group('Help')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    exec "$HOME/.local/share/ucli/scripts/check/check.sh" "$HOME"

# Validate package arrays.
[group('Help')]
validate:
    @~/.local/share/ucli/scripts/install/validate-packages.sh

# Print config paths.
_paths:
    @printf '%s\n' '~/.zshrc' '~/.config/zsh' '~/.config/ucli' \
    '~/.config/distrobox/dev.ini' '~/.config/distrobox/devbox.env' \
    '~/.config/distrobox/provision-dev.sh' \
    '~/.config/dev-services/compose.yml' '~/.local/bin/ucli' \
    '~/.local/share/chezmoi'
