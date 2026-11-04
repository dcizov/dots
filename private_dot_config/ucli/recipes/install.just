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
[private]
setup-cli:
    # alias of `ucli cli`: shell tier (zsh, oh-my-zsh, plugins, starship) + cosmetics
    @~/.local/share/ucli/scripts/install/install-shell.sh
    @~/.local/share/ucli/scripts/install/install-packages.sh cli

# Alias of `ucli apps`, for symmetry with setup-system/setup-desktop/setup-cli.
[private]
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

# Install personal apps and overrides (the `apps` step of `ucli setup-system`).
[group('Install')]
apps *ARGS:
    # personal apps and desktop overrides (bitwarden, firefox, spotify flatpak, …)
    # the Firefox profile itself (Betterfox, GNOME theme) comes with the browser
    @~/.local/share/ucli/scripts/install/install-overrides.sh {{ARGS}}

# Syncthing: keep a folder in sync between two machines (Bluefin's "Sync Folder",
# without the tray applet). Installs the daemon, enables syncthing@<user>.service
# and prints the Web GUI + this machine's device ID; pairing stays two clicks.
# Keep a folder in sync between two machines (Syncthing).
[group('Install')]
sync *ARGS:
    # --status shows the service + device ID, --no-service installs only
    @~/.local/share/ucli/scripts/install/install-sync.sh {{ARGS}}

# Virtual machines: qemu + libvirt + virt-manager on KVM. Not part of `ucli
# devmode` — a dev box is a container, a VM is for other operating systems and
# installer tests. Enables libvirtd, adds you to the `libvirt` group and starts
# libvirt's default NAT network, so guests get an address out of the box.
# Set up virtual machines (qemu + libvirt + virt-manager).
[group('Install')]
virt *ARGS:
    # --status shows packages, /dev/kvm, group, daemon and the default network
    @~/.local/share/ucli/scripts/install/install-virt.sh {{ARGS}}

# Microsoft's core fonts (Arial, Times New Roman, Courier New, …) from the AUR.
# The desktop step installs them too; this is the deliberate retry, because the
# build downloads from SourceForge and that does fail now and then.
# Install the Microsoft core fonts (AUR ttf-ms-fonts).
[group('Install')]
ms-fonts:
    @~/.local/share/ucli/scripts/install/install-packages.sh --yes fonts-ms

# Install paru idempotently (AUR helper).
[private]
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
[private]
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

