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
  ufw
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
  python-pipx  # needed to install gnome-extensions-cli (gext)
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

# GNOME desktop packages — Arch Linux package group `gnome` (59 packages)
# Source: https://archlinux.org/groups/x86_64/gnome/
#
# ArchWiki: "gnome contains the base GNOME desktop and the well-integrated
# core applications" — https://wiki.archlinux.org/title/GNOME
#
# Full group includes: baobab decibels epiphany gdm gnome-backgrounds
# gnome-calculator gnome-calendar gnome-characters gnome-clocks
# gnome-color-manager gnome-connections gnome-console gnome-contacts
# gnome-control-center gnome-disk-utility gnome-font-viewer gnome-keyring
# gnome-logs gnome-maps gnome-menus gnome-music gnome-remote-desktop
# gnome-session gnome-settings-daemon gnome-shell gnome-software
# gnome-system-monitor gnome-text-editor gnome-tour gnome-user-docs
# gnome-user-share gnome-weather grilo-plugins gst-thumbnailers gvfs
# gvfs-afc gvfs-dnssd gvfs-goa gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-onedrive
# gvfs-smb gvfs-wsdd loupe malcontent nautilus orca papers rygel showtime
# simple-scan snapshot sushi tecla xdg-desktop-portal-gnome xdg-user-dirs-gtk yelp
#
# If you want a debloated GNOME, replace `gnome` below with only the packages
# you actually need (see `pacman -Qe | grep gnome` for what's installed).
# Core essentials you almost certainly want: gnome-shell gdm nautilus
# gnome-control-center gnome-session gnome-keyring xdg-desktop-portal-gnome
DESKTOP_GNOME_BASE=(
  gnome
  gnome-tweaks
)

# ArchWiki: "gnome-shell-extensions package provides a set of very useful
# extensions maintained as part of the GNOME project."
# https://wiki.archlinux.org/title/GNOME#Advanced_settings
GNOME_SYSTEM_EXTENSION_PACKAGES=(
  gnome-shell-extensions
  gnome-shell-extension-caffeine
  gnome-shell-extension-appindicator
)

# extensions.gnome.org primary keys for Bluefin-like default UX.
# PK→UUID mapping (must stay parallel):
#   307  → dash-to-dock@micxgx.gmail.com
#   517  → caffeine@patapon.info
#   1319 → appindicatorsupport@rgcjonas.gmail.com
#   9975 → BetterTrayIcons@nexaknight.com
#   3193 → blur-my-shell@aunetx
#   5489 → gsconnect@andyholmes.github.io
#   10070 → user-accent-colors@fabito02
# search-light@icedman.github.com has no PK (UUID-only enable)
GNOME_SYSTEM_EXTENSION_PKS=(
  307
  517
  1319
  3193
  5489
)

GNOME_SYSTEM_EXTENSION_UUIDS=(
  dash-to-dock@micxgx.gmail.com
  caffeine@patapon.info
  appindicatorsupport@rgcjonas.gmail.com
  blur-my-shell@aunetx
  gsconnect@andyholmes.github.io
  search-light@icedman.github.com
)

# Personal extensions (not system UX) — installed via gext by install-gnome-extension-set.sh overrides
GNOME_OVERRIDE_EXTENSION_PKS=(
  3843
  4451
  97
  8834
  7048
  4158
  9975
  10070
)

GNOME_OVERRIDE_EXTENSION_UUIDS=(
  just-perfection-desktop@just-perfection
  logomenu@aryan_k
  CoverflowAltTab@palatis.blogspot.com
  copyous@boerdereinar.dev
  rounded-window-corners@fxgn
  gnome-ui-tune@itstime.tech
  BetterTrayIcons@nexaknight.com
  user-accent-colors@fabito02
)

# ArchWiki: gnome-boxes, gdm-settings, nautilus-* are all optional — remove
# any you don't use to debloat your GNOME install.
# https://wiki.archlinux.org/title/GNOME
GNOME_APP_OVERRIDES=(
  ghostty
  gnome-boxes            # VM manager — remove if you don't use VMs
  gdm-settings           # GDM theme/config — remove if defaults are OK
  nautilus-admin-gtk4    # Nautilus extension — remove if you don't use Nautilus
  nautilus-my-computer   # Nautilus extension — remove if you don't use Nautilus
  nautilus-open-any-terminal  # Nautilus extension — remove if you don't use Nautilus
  extension-manager      # GNOME Extension Manager GUI (AUR package)
)

# ArchWiki: gnome-tweaks — "Allows adjusting advanced GNOME options"
# https://wiki.archlinux.org/title/GNOME#Advanced_settings
# ArchWiki: gnome-shell-extensions — extensions maintained as part of GNOME
# https://wiki.archlinux.org/title/GNOME#Advanced_settings

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

# ArchWiki: gdm is the display manager included in the gnome group.
# https://wiki.archlinux.org/title/GNOME#Starting
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

  shelly-flatpak-backend
)

# Shelly is an AUR package (Seafoam-Labs/Shelly-ALPM), not a Flatpak.
# https://aur.archlinux.org/packages/shelly
MANUAL_AUR=(
  shelly
)

# -----------------------------
# Software replacement matrix
# -----------------------------
#
# When installing a desktop environment, some packages from the DE group may
# be unwanted or have better alternatives. This matrix defines:
#
#   DESKTOP_SKIP_<DE>   - packages from the DE group to NOT install
#   DESKTOP_REPLACE_<DE> - package -> replacement pairs
#
# Replacements are installed instead of the skipped package. If no replacement
# is listed, the package is simply not installed (debloat).
#
# Examples:
#   - gnome-software → shelly (AUR package: shelly in MANUAL_AUR)
#   - gnome-system-monitor → mission-center (flatpak: io.missioncenter.MissionCenter in GNOME_FLATPAKS)
#   - htop → btop (btop in SYSTEM_QOL_TOOLS)
#   - gnome-console → ghostty (already configured via chezmoi)
#
# ArchWiki: users should install only what they need from DE groups
# https://wiki.archlinux.org/title/GNOME

# GNOME packages to skip (debloat) — none skipped by default
DESKTOP_SKIP_GNOME=()

# GNOME package replacements: "original=replacement"
DESKTOP_REPLACE_GNOME=(
  "gnome-software=shelly"           # shelly is the graphical software manager
  "gnome-system-monitor=mission-center"  # mission-center flatpak
  "gnome-console=ghostty"           # ghostty is the configured terminal
  "htop=btop"                       # btop in SYSTEM_QOL_TOOLS
)

# Hyprland packages to skip
DESKTOP_SKIP_HYPRLAND=()

# Hyprland package replacements
DESKTOP_REPLACE_HYPRLAND=()

# KDE packages to skip
DESKTOP_SKIP_KDE=()

# KDE package replacements
DESKTOP_REPLACE_KDE=()

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
)

GAMING_FLATPAKS=()
