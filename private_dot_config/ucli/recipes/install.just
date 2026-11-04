# Set up the machine: base packages + desktop (DE, firefox, terminal, shell, snapshot).
[group('Install')]
setup-system *ARGS:
    # base packages + desktop step (pass gnome/kde/hyprland, or omit to prompt)
    @~/.local/share/ucli/scripts/install/install-profile.sh {{ARGS}}

# Add the shell cosmetics on top of the shell tier: eza, bat, zoxide, atuin, …
[group('Install')]
cli:
    # shell tier first (zsh, oh-my-zsh, plugins, starship), then the cosmetics
    @~/.local/share/ucli/scripts/install/install-shell.sh
    @~/.local/share/ucli/scripts/install/install-packages.sh cli

# Alias of `ucli cli`, for symmetry with setup-system/setup-desktop/setup-apps.
[group('Install')]
setup-cli:
    # alias of `ucli cli`: shell tier (zsh, oh-my-zsh, plugins, starship) + cosmetics
    @~/.local/share/ucli/scripts/install/install-shell.sh
    @~/.local/share/ucli/scripts/install/install-packages.sh cli

# Alias of `ucli apps`, for symmetry with setup-system/setup-desktop/setup-cli.
[group('Install')]
setup-apps *ARGS:
    # alias of `ucli apps`: firefox + terminal + personal apps, flatpaks, Firefox extensions
    @~/.local/share/ucli/scripts/install/install-overrides.sh {{ARGS}}

# `ucli devmode` flags:
#   ucli devmode           wizard on a TTY, everything otherwise
#   ucli devmode --all     every item, no menu
#   ucli devmode --status  marker + version gates
# Re-running offers "add more tools?" and preselects the previous picks.
# Set up developer tools (interactive wizard, like `ujust devmode`).
[group('Install')]
devmode *ARGS:
    # opt-in dev-cli + developer packages (vscodium, podman, distrobox, …)
    @~/.local/share/ucli/scripts/install/install-dev-profile.sh {{ARGS}}

# Install gaming profile.
[group('Install')]
gaming:
    # opt-in gaming packages (steam, mangohud, gamemode, lib32-*)
    @~/.local/share/ucli/scripts/install/install-gaming-profile.sh

# Install personal apps and overrides (`ucli setup-apps` is the same thing).
[group('Install')]
apps *ARGS:
    # personal apps and desktop overrides (bitwarden, firefox, spotify flatpak, …)
    # the Firefox profile itself (Betterfox, GNOME theme) comes with the browser
    @~/.local/share/ucli/scripts/install/install-overrides.sh {{ARGS}}

# Install paru idempotently (AUR helper).
[group('Install')]
install-paru:
    # install paru with PGP signature verification
    @~/.local/share/ucli/scripts/install/install-paru.sh

# Install VSCodium extensions (skipped when extensions.txt is unchanged).
[group('Install')]
vscodium-extensions *ARGS:
    # install configured VSCodium extensions (--force to reinstall)
    @~/.local/share/ucli/scripts/install/install-vscodium-extensions.sh {{ARGS}}

# Install gnome-extensions-cli (gext) via pipx.
# Required before running install-gnome-extension-set.sh.
[group('Install')]
install-gnome-extensions-cli:
    # install gnome-extensions-cli (gext) for GNOME extension management
    @~/.local/share/ucli/scripts/install/install-gnome-extensions-cli.sh

# Apply chezmoi-managed dotfiles.
[group('Install')]
chezmoi-apply:
    # deploy dotfiles from the repo to $HOME
    chezmoi apply -v

# Reverse what chezmoi/ucli deployed in this user's home directory.
# Removes chezmoi-managed dotfiles, ucli wrapper, and ucli-installed packages.
[group('Install')]
uninstall *ARGS:
    # reverse chezmoi/ucli deployment (--no-snapshot skips the restore point)
    @~/.local/share/ucli/scripts/install/uninstall.sh {{ARGS}}

# --- internal recipes (used by menus, not top-level) ---

# Install desktop profile only.
_setup-desktop:
    @~/.local/share/ucli/scripts/install/install-desktop-profile.sh

# Install shell setup (zsh + oh-my-zsh + plugins + starship).
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
