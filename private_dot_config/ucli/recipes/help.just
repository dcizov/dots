# Show common flows.
[group('Help')]
usage:
    @printf '%s\n' 'Day to day:'
    @printf '%s\n' '  ucli update      # pacman + AUR + flatpaks + dev box'
    @printf '%s\n' '  ucli logs        # this boot / last boot / devbox / pacman'
    @printf '%s\n' '  ucli clean-system'
    @printf '%s\n' ''
    @printf '%s\n' 'Setup:'
    @printf '%s\n' '  ucli setup-snapshots   # snapper + limine (skips CachyOS)'
    @printf '%s\n' '  ucli setup-desktop     # install DE + snapshot (Arch minimal)'
    @printf '%s\n' '  ucli debloat-desktop   # remove DE packages you do not need'
    @printf '%s\n' '  ucli setup-system      # base packages + shell'
    @printf '%s\n' '  ucli cli               # shell CLI experience'
    @printf '%s\n' '  ucli devmode           # developer tools (+ dev box)'
    @printf '%s\n' '  ucli gaming            # gaming profile'
    @printf '%s\n' '  ucli apps              # personal apps and overrides'
    @printf '%s\n' '  ucli install-paru      # AUR helper (idempotent)'
    @printf '%s\n' '  ucli vscodium-extensions'
    @printf '%s\n' '  ucli chezmoi-apply     # deploy dotfiles'
    @printf '%s\n' '  ucli devbox-reconcile  # create/update dev box'
    @printf '%s\n' ''
    @printf '%s\n' 'GNOME:'
    @printf '%s\n' '  ucli gnome             # extensions, settings backup/restore'
    @printf '%s\n' '  ucli backup-gnome-settings'
    @printf '%s\n' '  ucli restore-gnome-settings'
    @printf '%s\n' ''
    @printf '%s\n' 'System:'
    @printf '%s\n' '  ucli setup-snapshots   # snapper + limine'
    @printf '%s\n' '  ucli system            # checks and maintenance helpers'
    @printf '%s\n' ''
    @printf '%s\n' 'Maintenance:'
    @printf '%s\n' '  ucli update            # full system upgrade'
    @printf '%s\n' '  ucli clean-system      # dangling images, old cache'
    @printf '%s\n' '  ucli report            # machine facts to file'
    @printf '%s\n' '  ucli bios / bios-info  # firmware settings'
    @printf '%s\n' '  ucli changelogs        # last pacman transaction'
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

# Check setup health.
[group('Help')]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "== chezmoi =="
    mkdir -p "$HOME/.cache/tmp"
    TMPDIR="$HOME/.cache/tmp" chezmoi doctor || true
    echo
    echo "== zsh =="
    zsh -n "$HOME/.zshrc"
    echo "OK: ~/.zshrc"
    echo
    echo "== commands =="
    for cmd in just chezmoi zsh git curl nano; do
    command -v "$cmd" >/dev/null 2>&1 && printf 'OK:      %s -> %s\n' "$cmd" "$(command -v "$cmd")" || printf 'MISSING: %s\n' "$cmd"
    done
    echo
    echo "== devbox =="
    if command -v distrobox >/dev/null 2>&1; then
    printf 'OK:      distrobox -> %s\n' "$(command -v distrobox)"
    if distrobox list --no-color 2>/dev/null | grep -qE '\bdev\b'; then
    # a container that exists but was never provisioned looks identical to a
    # healthy one unless we ask about the versions the tooling assumes
    out="$(distrobox enter dev -- bash -lc \
    'printf "%s|%s|%s\n" "$(cat /etc/debian_version)" \
    "$(node -v 2>/dev/null || echo MISSING)" \
    "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"' 2>/dev/null || true)"
    debian="${out%%|*}"; rest="${out#*|}"; node="${rest%%|*}"; php="${rest##*|}"
    if [[ -n "$debian" && "$node" != MISSING && "$php" != MISSING ]]; then
    printf 'OK:      dev: debian %s / node %s / php %s\n' "$debian" "$node" "$php"
    else
    printf 'INCOMPLETE: dev exists but is not provisioned (node %s, php %s)\n' \
    "${node:-?}" "${php:-?}"
    printf '         run: ucli devbox-reconcile (or ucli devbox-reprovision)\n'
    fi
    else
    printf 'MISSING: container dev (ucli devbox-reconcile)\n'
    fi
    else
    printf 'MISSING: distrobox\n'
    fi

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
