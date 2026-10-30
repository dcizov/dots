# Set up the machine profile.
setup-system:
    ~/.config/ucli/scripts/install/install-profile.sh

# Set up shell CLI experience.
cli:
    ~/.config/ucli/scripts/install/install-packages.sh cli

# Set up developer tools.
devmode:
    ~/.config/ucli/scripts/install/install-dev-profile.sh

# Install gaming profile.
gaming:
    ~/.config/ucli/scripts/install/install-gaming-profile.sh

# Install personal apps and overrides.
apps:
    ~/.config/ucli/scripts/install/install-overrides.sh

# Optional extras picker.
_extras:
    #!/usr/bin/env bash
    set -euo pipefail
    items=(
      'cli|Set up shell CLI experience'
      'devmode|Set up developer tools'
      'gaming|Install gaming profile'
      'apps|Install personal apps and overrides'
      'shell-overrides|Install explicit shell override packages'
      'full-setup|Install system profile plus cli/dev/gaming'
      'shell|Install Oh My Zsh and fzf-tab'
      'paru|Install paru idempotently'
    )
    if command -v fzf >/dev/null 2>&1; then
      choice="$(printf '%s\n' "${items[@]}" | fzf --prompt='extras> ' --with-nth=1,2 --delimiter='|')" || exit 0
      choice="${choice%%|*}"
    else
      select item in "${items[@]}"; do choice="${item%%|*}"; break; done
    fi
    case "$choice" in
      cli) ~/.config/ucli/scripts/install/install-packages.sh cli ;;
      devmode) ~/.config/ucli/scripts/install/install-dev-profile.sh ;;
      gaming) ~/.config/ucli/scripts/install/install-gaming-profile.sh ;;
      apps) ~/.config/ucli/scripts/install/install-overrides.sh ;;
      shell-overrides) ~/.config/ucli/scripts/install/install-packages.sh shell-overrides ;;
      full-setup)
        ~/.config/ucli/scripts/install/install-packages.sh full
        ~/.config/ucli/scripts/install/install-shell.sh
        ~/.config/ucli/scripts/install/install-flatpaks.sh full
        ;;
      shell) ~/.config/ucli/scripts/install/install-shell.sh ;;
      paru) ~/.config/ucli/scripts/install/install-paru.sh ;;
    esac

# Install first-machine profile.
_install-profile:
    ~/.config/ucli/scripts/install/install-profile.sh

# Install desktop profile only.
_setup-desktop:
    ~/.config/ucli/scripts/install/install-desktop-profile.sh

# Install shell setup.
_shell:
    ~/.config/ucli/scripts/install/install-shell.sh

# Install explicit shell override packages.
_shell-overrides:
    ~/.config/ucli/scripts/install/install-packages.sh shell-overrides

# Reinstall/enable default GNOME system extensions.
_gnome-system-extensions:
    ~/.config/ucli/scripts/install/install-gnome-extension-set.sh system

# Install full setup including opt-in cli/dev/gaming.
_full-setup:
    ~/.config/ucli/scripts/install/install-packages.sh full
    ~/.config/ucli/scripts/install/install-shell.sh
    ~/.config/ucli/scripts/install/install-flatpaks.sh full

# Install paru idempotently.
_install-paru:
    ~/.config/ucli/scripts/install/install-paru.sh
