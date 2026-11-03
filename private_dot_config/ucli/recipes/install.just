# Set up the machine profile.
[group('Install')]
setup-system:
    # bootstrap + cpu + gpu + zsh + system-tools + fonts + desktop
    @~/.config/ucli/scripts/install/executable_install-profile.sh

# Set up shell CLI experience.
[group('Install')]
cli:
    # opt-in shell CLI experience (atuin, fd, bat, eza, starship, …)
    @~/.config/ucli/scripts/install/executable_install-packages.sh cli

# Set up developer tools.
[group('Install')]
devmode:
    # opt-in dev-cli + developer packages (vscodium, podman, distrobox, …)
    @~/.config/ucli/scripts/install/executable_install-dev-profile.sh

# Install gaming profile.
[group('Install')]
gaming:
    # opt-in gaming packages (steam, mangohud, gamemode, lib32-*)
    @~/.config/ucli/scripts/install/executable_install-gaming-profile.sh

# Install personal apps and overrides.
[group('Install')]
apps:
    # personal apps and desktop overrides (bitwarden, firefox, spotify flatpak, …)
    @~/.config/ucli/scripts/install/executable_install-overrides.sh

# Install paru idempotently (AUR helper).
[group('Install')]
install-paru:
    # install paru with PGP signature verification
    @~/.config/ucli/scripts/install/executable_install-paru.sh

# Install VSCodium extensions.
[group('Install')]
vscodium-extensions:
    # install configured VSCodium extensions
    @~/.config/ucli/scripts/install/executable_install-vscodium-extensions.sh

# Apply chezmoi-managed dotfiles.
[group('Install')]
chezmoi-apply:
    # deploy dotfiles from the repo to $HOME
    chezmoi apply -v

# Reverse what chezmoi/ucli deployed in this user's home directory.
# Removes chezmoi-managed dotfiles, ucli wrapper, and ucli-installed packages.
[group('Install')]
uninstall:
    # reverse chezmoi/ucli deployment
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
