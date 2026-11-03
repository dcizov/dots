# Package sets for ucli.
# Resolver policy:
# - exact package/group names only
# - pacman repo/group first
# - AUR fallback through paru
# - GNOME extension packages stay repo-only; non-repo extensions use extensions.gnome.org API scripts

# ------------------------------------------------------------------
# Desktop Environment notes (archinstall vs CachyOS Calamares)
#
# archinstall (script/TUI, on Arch minimal):
#   - Profile: Desktop -> pick DE (gnome, kde, hyprland, ...)
#   - GNOME:   gnome gnome-tweaks gdm + enable gdm
#   - Hyprland: hyprland hyprpaper xdg-desktop-portal-hyprland waybar wofi kitty sddm
#   - Vanilla Arch packages, no distro-specific theming
#
# CachyOS Calamares (GUI, on CachyOS):
#   - 17+ DE choices during install (KDE Plasma, GNOME, COSMIC, Hyprland, Niri, ...)
#   - Each DE gets distro-specific settings packages (e.g. cachyos-hyprland-settings,
#     cachyos-kde-settings) + CPU-optimized builds + tuned kernel
#   - Calamares handles Snapper/Limine + DE during install; skip ucli setup-snapshots
#   - On CachyOS you pick DE in the installer, not manually after boot
#
# This repo's DESKTOP_* arrays are for manual post-install DE setup on Arch minimal.
# On CachyOS, DE is already installed by Calamares; use these arrays only to add
# or adjust packages afterward.
# ------------------------------------------------------------------

# -----------------------------
# Base setup
# -----------------------------

BOOTSTRAP=(
  git
  chezmoi
  just
  zsh
  openssh
  curl
  nano
  less
  rsync
  wget
)

# Deliberately empty: these three used to be installed as Arch packages, which
# put them in /usr/share/zsh/plugins — a location the dev box (Debian) does not
# have. They are now cloned into $ZSH_CUSTOM/plugins by install-shell.sh and
# loaded by oh-my-zsh's plugins=() array, so both systems run the same files
# from the same place. Kept as an (empty) array because install-packages.sh and
# validate-packages.sh reference it by name.
ZSH=()

SYSTEM_CORE_TOOLS=(
  expac
  pkgfile
  pacman-contrib
  smartmontools
)

SYSTEM_QOL_TOOLS=(
  btop
  fastfetch
  restic
)

CPU_INTEL=(intel-ucode)
CPU_AMD=(amd-ucode)

GPU_AMD=(
  mesa
  vulkan-radeon
)

GPU_INTEL=(
  intel-media-driver
  libva-intel-driver
  vulkan-intel
)

GPU_NVIDIA=(
  nvidia
  nvidia-utils
  lib32-nvidia-utils
)

SYSTEM_SUPPORT=(
  gufw
  fprintd
)

BOOT_SUPPORT=(
  plymouth
)

SNAPSHOT_LIMINE=(
  btrfs-progs
  snapper
  snap-pac
  limine
  limine-snapper-sync
  limine-mkinitcpio-hook
)

FONTS_THEMES=(
  ttf-jetbrains-mono
  ttf-jetbrains-mono-nerd
  adw-gtk-theme
  papirus-icon-theme
)

# -----------------------------
# Opt-in CLI / dev / gaming
# -----------------------------

CLI=(
  atuin
  fd
  bat
  tealdeer
  eza
  zoxide
  duf
  ripgrep
  fzf
  gum          # menu backend for ucli (ujust uses it too)
  starship
  glow
  direnv
  mise
  tree
)

DEV_CLI=(
  jq
  yq
  lazygit
  neovim
  vim
  tmux
  shfmt
)

DEV=(
  base-devel
  podman
  distrobox
  docker
  docker-compose
  docker-buildx
  podman-desktop
  vscodium-bin
  vscodium-bin-marketplace
)

GAMING=(
  steam
  mangohud
  gamemode
  lib32-mangohud
  lib32-gamemode
)

# -----------------------------
# GNOME
# -----------------------------

# ArchWiki: the gnome group contains the base GNOME desktop and core apps.
# Core: gnome (shell, core apps), gdm (display manager).
# Optional / removable if you don't need them:
#   gnome-tweaks              -- appearance customization (remove if you don't tweak)
#   gnome-boxes               -- VM manager (remove if you don't use VMs)
#   gdm-settings              -- GDM theme/config (remove if you leave defaults)
#   nautilus-* extensions     -- file manager extras (remove if you don't use Nautilus)
DESKTOP_GNOME_BASE=(
  gnome
  gnome-tweaks
)

# Repo-packaged default extensions. Non-repo defaults are installed by API script.
GNOME_SYSTEM_EXTENSION_PACKAGES=(
  gnome-shell-extensions
  gnome-shell-extension-caffeine
  gnome-shell-extension-appindicator
)

# extensions.gnome.org primary keys for Bluefin-like default UX.
# dash-to-dock, gsconnect, blur-my-shell, search-light
GNOME_SYSTEM_EXTENSION_PKS=(
  307
  1319
  3193
  5489
)

GNOME_SYSTEM_EXTENSION_UUIDS=(
  caffeine@patapon.info
  appindicatorsupport@rgcjonas.gmail.com
  dash-to-dock@micxgx.gmail.com
  gsconnect@andyholmes.github.io
  blur-my-shell@aunetx
  search-light@icedman.github.com
)

GNOME_APP_OVERRIDES=(
  ghostty
  gnome-boxes
  gdm-settings
  nautilus-admin-gtk4
  nautilus-my-computer
  nautilus-open-any-terminal
)

# extensions.gnome.org primary keys for personal extensions.
# just-perfection, logo-menu, coverflow-alt-tab, copyous, rounded-window-corners-reborn, gnome-ui-tune
GNOME_OVERRIDE_EXTENSION_PKS=(
  3843
  4451
  97
  8834
  7048
  4158
)

GNOME_OVERRIDE_EXTENSION_UUIDS=(
  just-perfection-desktop@just-perfection
  logomenu@aryan_k
  CoverflowAltTab@palatis.blogspot.com
  copyous@boerdereinar.dev
  rounded-window-corners@fxgn
  gnome-ui-tune@itstime.tech
)

GNOME_SHELL_OVERRIDES=(
  gnome-rounded-blur
)

SERVICES_GNOME=(
  gdm
)

# -----------------------------
# Hyprland / KDE

# Hyprland essentials: compositor + bar/launcher + portal + session tools.
# Optional / removable:
#   kitty        -- terminal (replace with ghostty/alacritty/foot if preferred)
#   dolphin      -- file manager (remove if you use another)
#   wofi         -- app launcher (remove if you use rofi/wofi alternatives)
#   grim/slurp   -- screenshot tools (remove if you don't screenshot)
# -----------------------------

DESKTOP_HYPRLAND_BASE=(
  hyprland
  dunst
  kitty
  uwsm
  dolphin
  wofi
  xdg-desktop-portal-hyprland
  qt5-wayland
  qt6-wayland
  polkit-kde-agent
  grim
  slurp
  wl-clipboard
  sddm
)

DESKTOP_HYPRLAND_ADDITIONS=()

SERVICES_HYPRLAND=(
  sddm
)

DESKTOP_KDE_BASE=()
DESKTOP_KDE_ADDITIONS=()

SERVICES_KDE=(
  sddm
)

# -----------------------------
# Personal apps
# -----------------------------

APPS=(
  bitwarden
  btrfs-assistant
  firefox
  fragments
  gparted
  webapp-manager

  deja-dup

  fuse2
  libinput-tools

  shelly
  shelly-flatpak-backend
)

MANUAL_AUR=()

# -----------------------------
# Flatpak app IDs
# -----------------------------

APP_FLATPAKS=(
  com.github.tchx84.Flatseal
  io.github.flattool.Warehouse
  io.github.flattool.Ignition
  io.github.giantpinkrobots.flatsweep
  io.github.vikdevelop.SaveDesktop
  me.timschneeberger.GalaxyBudsClient
  app.drey.Warp
  com.warlordsoftwares.wallpaper-app-4kwall
  com.usebottles.bottles
  com.spotify.Client
  com.vencord.Vesktop
  md.obsidian.Obsidian
	com.spotify.Client
	dev.vencord.Vesktop
)

GNOME_FLATPAKS=(
  dev.qwery.AddWater
  io.github.swordpuffin.rewaita
  io.github.swordpuffin.wardrobe
  io.missioncenter.MissionCenter
  page.tesk.Refine
  io.github.nacho.mecalin
  io.gitlab.adhami3310.Impression
)

HYPRLAND_FLATPAKS=()
KDE_FLATPAKS=()

DEV_FLATPAKS=(
  me.iepure.devtoolbox
  com.ranfdev.DistroShelf
)

GAMING_FLATPAKS=()
