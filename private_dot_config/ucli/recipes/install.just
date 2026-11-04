# Set up the machine profile (no shell opinion — use `ucli cli` for that).
[group('Install')]
setup-system:
    # bootstrap + cpu + gpu + system-tools + fonts + desktop + ucli runtime
    @~/.local/share/ucli/scripts/install/install-profile.sh

# Set up the shell experience: oh-my-zsh + plugins + zsh as login shell, then
# the cosmetic tooling (starship, eza, bat, zoxide, atuin, …).
[group('Install')]
cli:
    # opt-in shell tier (oh-my-zsh, plugins, prompt, aliases, fuzzy find)
    @~/.local/share/ucli/scripts/install/install-packages.sh cli
    @~/.local/share/ucli/scripts/install/install-shell.sh

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
