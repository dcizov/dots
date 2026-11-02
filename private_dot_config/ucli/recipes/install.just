# Set up the machine profile.
[group('Install')]
setup-system:
    ~/.config/ucli/scripts/install/install-profile.sh

# Set up shell CLI experience.
[group('Install')]
cli:
    ~/.config/ucli/scripts/install/install-packages.sh cli

# Set up developer tools.
[group('Install')]
devmode:
    ~/.config/ucli/scripts/install/install-dev-profile.sh

# Install gaming profile.
[group('Install')]
gaming:
    ~/.config/ucli/scripts/install/install-gaming-profile.sh

# Install personal apps and overrides.
[group('Install')]
apps:
    ~/.config/ucli/scripts/install/install-overrides.sh

# Picker for the opt-in extras (shell, paru, overrides, full setup).
[group('Install')]
extras:
    #!/usr/bin/env bash
    set -euo pipefail
    . "$HOME/.config/ucli/scripts/lib/choose.sh"
    ucli_bin="$(command -v ucli || printf '%s' "$HOME/.local/bin/ucli")"
    choice="$(ui_choose 'extras' \
      'cli|Set up shell CLI experience' \
      'devmode|Set up developer tools (includes the dev box)' \
      'gaming|Install gaming profile' \
      'apps|Install personal apps and overrides' \
      'shell-overrides|Install explicit shell override packages' \
      'full-setup|Install system profile plus cli/dev/gaming' \
      'shell|Install Oh My Zsh and fzf-tab' \
      'paru|Install paru idempotently')" || exit 0
    case "$choice" in
      cli)             exec "$ucli_bin" cli ;;
      devmode)         exec "$ucli_bin" devmode ;;
      gaming)          exec "$ucli_bin" gaming ;;
      apps)            exec "$ucli_bin" apps ;;
      shell-overrides) exec "$ucli_bin" _shell-overrides ;;
      full-setup)      exec "$ucli_bin" _full-setup ;;
      shell)           exec "$ucli_bin" _shell ;;
      paru)            exec "$ucli_bin" _install-paru ;;
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

# Reverse what chezmoi/ucli deployed in this user's home directory.
# Removes chezmoi-managed dotfiles, ucli wrapper, and ucli-installed packages.
[group('Install')]
uninstall:
    ~/.config/ucli/scripts/install/uninstall.sh
