# Set up the machine profile.
[group('Install')]
setup-system:
    # bootstrap + cpu + gpu + zsh + system-tools + fonts + desktop
    @~/.local/share/ucli/scripts/install/install-profile.sh

# Set up shell CLI experience.
[group('Install')]
cli:
    # opt-in shell CLI experience (atuin, fd, bat, eza, starship, …)
    @~/.local/share/ucli/scripts/install/install-packages.sh cli

# Set up developer tools.
[group('Install')]
devmode:
    # opt-in dev-cli + developer packages (vscodium, podman, distrobox, …)
    @~/.local/share/ucli/scripts/install/install-dev-profile.sh

# Install gaming profile.
[group('Install')]
gaming:
    # opt-in gaming packages (steam, mangohud, gamemode, lib32-*)
    @~/.local/share/ucli/scripts/install/install-gaming-profile.sh

# Install personal apps and overrides.
[group('Install')]
apps:
    # personal apps and desktop overrides (bitwarden, firefox, spotify flatpak, …)
    @~/.local/share/ucli/scripts/install/install-overrides.sh

# Install paru idempotently (AUR helper).
[group('Install')]
install-paru:
    # install paru with PGP signature verification
    @~/.local/share/ucli/scripts/install/install-paru.sh

# Install VSCodium extensions.
[group('Install')]
vscodium-extensions:
    # install configured VSCodium extensions
    @~/.local/share/ucli/scripts/install/install-vscodium-extensions.sh

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
    @~/.local/share/ucli/scripts/install/uninstall.sh

# --- internal recipes (used by menus, not top-level) ---

# Install desktop profile only.
_setup-desktop:
    @~/.local/share/ucli/scripts/install/install-desktop-profile.sh

# Install shell setup.
_shell:
    @~/.local/share/ucli/scripts/install/install-shell.sh

# Install explicit shell override packages.
_shell-overrides:
    @~/.local/share/ucli/scripts/install/install-packages.sh shell-overrides

# Reinstall/enable default GNOME system extensions.
_gnome-system-extensions:
    @~/.local/share/ucli/scripts/install/install-gnome-extension-set.sh system

# Install full setup including opt-in cli/dev/gaming.
_full-setup:
    @~/.local/share/ucli/scripts/install/install-packages.sh full
    @~/.local/share/ucli/scripts/install/install-shell.sh
    @~/.local/share/ucli/scripts/install/install-flatpaks.sh full
