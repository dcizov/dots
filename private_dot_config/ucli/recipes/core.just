# Pick a command.
_choose:
    @ucli --choose

# Show common flows.
usage:
    @printf '%s\n' 'Setup:'
    @printf '%s\n' '  chezmoi init/apply'
    @printf '%s\n' '  ucli setup-snapshots'
    @printf '%s\n' '  ucli setup-system'
    @printf '%s\n' '  ucli devbox-reconcile
    @printf '%s\n' ''
    @printf '%s\n' 'Browse commands:'
    @printf '%s\n' '  ucli --choose'
    @printf '%s\n' ''
    @printf '%s\n' 'Optional:'
    @printf '%s\n' '  ucli cli       # shell CLI experience'
    @printf '%s\n' '  ucli devmode   # developer tools'
    @printf '%s\n' '  ucli gaming    # gaming profile'
    @printf '%s\n' '  ucli apps      # personal apps and overrides'
    @printf '%s\n' '  ucli system    # checks and maintenance helpers'
    @printf '%s\n' '  ucli gnome     # GNOME helpers'
    @printf '%s\n' '  ucli devbox    # distrobox box: reconcile/recreate/versions/log'
    @printf '%s\n' ''
    @printf '%s\n' 'Direct tools:'
    @printf '%s\n' '  chezmoi diff && chezmoi apply -v'
    @printf '%s\n' '  ucli devbox-reconcile    # creates or updates the box'
    @printf '%s\n' '  ucli devbox-recreate     # rebuild on a new Debian base'
    @printf '%s\n' '  cd ~/.config/dev-services && docker compose up -d'

# Show configured and detected profile data.
profile:
    ~/.config/ucli/scripts/system/detect.sh

# Check setup health.
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
        distrobox enter dev -- bash -lc \
          'printf "OK:      dev: debian %s / node %s / php %s\n" \
             "$(cat /etc/debian_version)" "$(node -v 2>/dev/null || echo MISSING)" \
             "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"' || true
      else
        printf 'MISSING: container dev (ucli devbox-reconcile)\n'
      fi
    else
      printf 'MISSING: distrobox\n'
    fi

# Validate package arrays.
validate:
    ~/.config/ucli/scripts/install/validate-packages.sh

# Show detected system facts.
_detect:
    ~/.config/ucli/scripts/system/detect.sh

# Print config paths.
_paths:
    @printf '%s\n' '~/.zshrc' '~/.config/zsh' '~/.config/ucli' \
      '~/.config/distrobox/dev.ini' '~/.config/distrobox/devbox.env' \
      '~/.config/distrobox/provision-dev.sh' \
      '~/.config/dev-services/compose.yml' '~/.local/bin/ucli' \
      '~/.local/share/chezmoi'
