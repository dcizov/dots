# Set up the machine profile.
[group('Install')]
setup-system:
    @~/.config/ucli/scripts/install/executable_install-profile.sh

# Set up shell CLI experience.
[group('Install')]
cli:
    @~/.config/ucli/scripts/install/executable_install-packages.sh cli

# Set up developer tools.
[group('Install')]
devmode:
    @~/.config/ucli/scripts/install/executable_install-dev-profile.sh

# Install gaming profile.
[group('Install')]
gaming:
    @~/.config/ucli/scripts/install/executable_install-gaming-profile.sh

# Install personal apps and overrides.
[group('Install')]
apps:
    @~/.config/ucli/scripts/install/executable_install-overrides.sh

# Install paru idempotently (AUR helper).
[group('Install')]
install-paru:
    @~/.config/ucli/scripts/install/executable_install-paru.sh

# Install VSCodium extensions.
[group('Install')]
vscodium-extensions:
    @~/.config/ucli/scripts/install/executable_install-vscodium-extensions.sh

# Apply chezmoi-managed dotfiles.
[group('Install')]
chezmoi-apply:
    chezmoi apply -v

# Reverse what chezmoi/ucli deployed in this user's home directory.
# Removes chezmoi-managed dotfiles, ucli wrapper, and ucli-installed packages.
[group('Install')]
uninstall:
    @~/.config/ucli/scripts/install/executable_uninstall.sh

# --- internal recipes (used by menus, not top-level) ---

# Install desktop profile only.
_setup-desktop:
    @~/.config/ucli/scripts/install/executable_install-desktop-profile.sh

# Install shell setup.
_shell:
    @~/.config/ucli/scripts/install/executable_install-shell.sh

# Install explicit shell override packages.
_shell-overrides:
    @~/.config/ucli/scripts/install/executable_install-packages.sh shell-overrides

# Reinstall/enable default GNOME system extensions.
_gnome-system-extensions:
    @~/.config/ucli/scripts/install/executable_install-gnome-extension-set.sh system

# Install full setup including opt-in cli/dev/gaming.
_full-setup:
    @~/.config/ucli/scripts/install/executable_install-packages.sh full
    @~/.config/ucli/scripts/install/executable_install-shell.sh
    @~/.config/ucli/scripts/install/executable_install-flatpaks.sh full
