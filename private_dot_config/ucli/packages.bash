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

# ------------------------------------------------------------------
# Machine settings — not packages, but the same kind of decision, and this
# is the file you already edit for "what this machine gets". Empty/unset
# means "work it out", so a fresh install needs no edits here.
# ------------------------------------------------------------------

# Which AUR helper to use. Empty = shelly if installed, else paru if installed,
# else paru on Arch / shelly on CachyOS (asking once when interactive). Set it to
# "paru" or "shelly" to make that choice explicit — it then wins even when the
# other helper is installed. Override it per machine in
# ~/.config/ucli/packages.local.bash; nothing is cached in a state file, so this
# is the only place the answer lives.
AUR_HELPER="${AUR_HELPER:-}"

# Extra kernel parameters, appended by `ucli setup-boot` to whatever the
# bootloader already has (limine's /etc/default/limine or its limine.conf). These
# are the CachyOS defaults — quiet boot, no watchdog chatter, no zswap — plus
# `splash` for plymouth. Existing parameters are preserved; this only adds what
# is missing, so it is safe to re-run.
KERNEL_CMDLINE_EXTRA=(
  quiet
  splash
  loglevel=3
  nowatchdog
  zswap.enabled=0
)

# Plymouth theme for that splash. Empty = leave plymouth's own default (Arch
# ships bgrt, which keeps the OEM logo, and falls back to a spinner when the
# firmware has none). `plymouth-set-default-theme -l` lists what is installed.
PLYMOUTH_THEME="${PLYMOUTH_THEME:-}"

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

# The shell tier proper: everything install-shell.sh puts in place. zsh (the
# shell and the omz installer's prerequisite), git (plugin clones), curl (the omz
# fetch) and starship (the prompt 99-prompt.zsh initialises). Installed by
# `install-shell.sh`, which `ucli setup-system`/`setup-desktop` and `ucli cli`
# all run — so starship is part of the shell, not a cosmetic extra.
SHELL_TOOLS=(
  zsh
  git
  curl
  starship
)

# zsh plugins are deliberately not Arch packages here: install-shell.sh clones
# them into $ZSH_CUSTOM/plugins, because the packages install into
# /usr/share/zsh/plugins and the dev box (Debian) has no such directory. There
# is therefore no zsh-plugin array at all — the shell itself is SHELL_TOOLS above.

SYSTEM_CORE_TOOLS=(
  expac
  pkgfile
  pacman-contrib
  smartmontools
  fwupd            # firmware/BIOS updates; GNOME's Firmware panel expects it
)

SYSTEM_QOL_TOOLS=(
  btop
  fastfetch
  restic
)

# Multimedia codecs. archinstall installs none of these (the gnome group pulls
# only gst-plugins-base through its own dependencies), and the symptom is a video
# that plays sound with no picture, or a browser that cannot decode h264.
SYSTEM_MEDIA_CODECS=(
  gst-plugins-good
  gst-plugins-bad
  gst-plugins-ugly
  gst-libav
  ffmpeg
)

# Installed only when the hardware is actually present — lib/detect.sh decides.
# A fingerprint reader without fprintd is dead weight, and libinput's CLI is only
# useful on a machine with a touchpad or trackpoint.
HARDWARE_FINGERPRINT=(fprintd)
HARDWARE_TOUCHPAD=(libinput-tools)

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

# Always installed. Hardware-specific support (fprintd, libinput-tools) lives in
# HARDWARE_* below and is only added when lib/detect.sh finds the device.
SYSTEM_SUPPORT=(
  gufw
  ufw
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

# The font set is not taste here: it is what the shipped configs ask for.
#   ghostty            font-family = JetBrainsMono Nerd Font
#   VSCodium editor    'Adwaita Mono', 'Cantarell Mono', 'JetBrains Mono'
#   VSCodium terminal  JetBrainsMono Nerd Font
# so both the plain and the Nerd Font variant are required. Nerd glyphs are what
# starship and the oh-my-zsh themes draw with; without the patched variant they
# render as boxes.
#
# Icons stay Adwaita + its legacy fallback, which is what Bluefin ships
# (adwaita-icon-theme + adwaita-icon-theme-legacy): Adwaita alone has very few
# third-party app icons. A full third-party set (Papirus, MoreWaita, …) is a
# taste — it lives in PERSONAL_PKGS and needs its own dconf value, since the
# shipped GNOME profile now points at Adwaita.
FONTS_THEMES=(
  ttf-jetbrains-mono
  ttf-jetbrains-mono-nerd
  adw-gtk-theme
  adwaita-icon-theme-legacy
)

# Microsoft's core fonts (Arial, Times New Roman, Courier New, Verdana, …) — the
# set every document, PDF and half the web expects and no Linux distro ships.
# Bluefin gets them from the Homebrew tap colindean/fonts-nonfree; on Arch the
# same fonts are the AUR package ttf-ms-fonts (the AUR's most-voted font
# package). Separate from FONTS_THEMES for one reason: it is AUR-only and its
# payload comes from SourceForge, so a failed build must not take the repo fonts
# down with it. Install with `ucli ms-fonts`.
FONTS_MS=(
  ttf-ms-fonts
)

# -----------------------------
# ucli runtime — not optional
# -----------------------------
# Installed by `base`, so `ucli setup-system` always leaves the CLI working:
# without gum the menus silently degrade to a numbered list, and without pipx
# `ucli install-gnome-extensions-cli` (gext) cannot run.
UCLI_RUNTIME=(
  gum          # menu backend for ucli (the ujust TUI)
  python-pipx  # installs gnome-extensions-cli (gext)
)

# -----------------------------
# Opt-in CLI / dev / gaming
# -----------------------------
# Two tiers, split on purpose rather than by convenience:
#   CLI      cosmetics — prompt, colours, aliases, history, fuzzy find, paging.
#            Nothing here is needed to build or run code; a shell just feels
#            worse without it.
#   DEV_CLI  plumbing — parse, search, navigate, edit, run. Needed the moment
#            you touch a repository, so it rides with `ucli devmode`.

# Shell cosmetics: the toys that sit on top of the shell tier. Nothing here is
# needed to get a working prompt — that is SHELL_TOOLS + oh-my-zsh.
CLI=(
  atuin
  bat
  eza
  fzf
  glow
  tealdeer
  zoxide
)

# Engineering plumbing.
# ugrep is here as its own command (`ug`): recursive by default, searches inside
# archives/PDFs, has an interactive -Q mode. `grep` is deliberately NOT aliased to
# it — ug changes pipeline behaviour (ug pattern recurses, grep waits on stdin)
# and that is not something to discover inside a script.
DEV_CLI=(
  direnv
  duf
  fd
  jq
  lazygit
  mise
  ripgrep
  shfmt
  tmux
  tree
  ugrep
  vim
  yq
)

DEV=(
  base-devel
  tailscale        # installed only; enable with: systemctl enable --now tailscaled
                   # (Bluefin ships it in the image, this is the Arch equivalent)
  podman
  distrobox
  docker
  docker-compose
  docker-buildx
  podman-desktop
  vscodium-bin
  vscodium-bin-marketplace
)

# Virtual machines — deliberately NOT part of `ucli devmode`: a dev box is a
# container (distrobox), a VM is for testing installers, other OSes and
# snapshots you would not run on the host. `qemu-desktop` is the full-system
# emulator (the `qemu-full` metapackage also drags every other target),
# `edk2-ovmf` gives UEFI guests, `swtpm` an emulated TPM 2.0 (Windows 11 wants
# one), `dnsmasq` backs libvirt's default NAT network. `ucli virt` enables
# libvirtd and puts you in the `libvirt` group; that is the whole install.
VIRT=(
  qemu-desktop
  libvirt
  virt-manager
  virt-viewer
  edk2-ovmf
  swtpm
  dnsmasq
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

# GNOME has no ADDITIONS tier: the gnome group is complete, and the optional
# extras (gnome-boxes, the Nautilus extensions) are GNOME_APP_OVERRIDES below —
# they belong to `ucli apps`, not to the desktop install. (Extension Manager is
# not in that list: it ships with the extension set below.) The empty array exists so setup-desktop can read
# DESKTOP_<DE>_BASE + DESKTOP_<DE>_ADDITIONS for every desktop alike.
DESKTOP_GNOME_ADDITIONS=()

# https://wiki.archlinux.org/title/GNOME#Advanced_settings
# GNOME extensions, two sources on purpose:
#
#   * pacman, when Extra packages that extension on its own: fewer moving parts,
#     updates with the rest of the system, files in /usr/share/gnome-shell/
#     extensions (Extension Manager calls those "System Extensions").
#   * gext / extensions.gnome.org, for everything the repos do not ship, or only
#     ship in a bundle. `user-theme` used to come from gnome-shell-extensions,
#     which is one 14-extension package: we wanted exactly one of the fourteen,
#     and it arrived disabled anyway, so it was dead weight in the System
#     Extensions list. It is PK 19 on EGO, maintained by GNOME's own fmuellner,
#     and now part of the managed set below — installed *and* enabled.
#
# These were parallel PKS/UUIDS arrays once, and they drifted: 1319 is GSConnect
# (the old list claimed appindicator support), 5489 is Search Light (the old list
# claimed GSConnect), and AppIndicator support is 615. Hence one "PK:UUID" entry
# per extension: PK is what `gext install` takes, UUID is what GNOME enables.
GNOME_SYSTEM_EXTENSION_PACKAGES=(
  gnome-shell-extension-caffeine             # keep the screen awake
  gnome-shell-extension-appindicator         # tray icons (615 on EGO)
  # libgda6 + gsound are Copyous' backends, and Copyous is not in the managed set
  # any more (it is a "sometimes" extension: see packages.local.bash.example).
  # They ride along with it in the overlay's PERSONAL_PKGS instead of being
  # installed on every machine for an extension that may never be enabled.
)

# Everything the extension step needs that is not itself an extension. Kept apart
# from the array above because "System Extensions" in Extension Manager means one
# precise thing — a package that drops an extension into /usr/share/gnome-shell/
# extensions — and a GUI, a zip binary and a screenshot app are none of those.
GNOME_EXTENSION_TOOLING=(
  extension-manager                          # the GUI for everything here:
                                             # browse/install/tune extensions
                                             # (0.6.5, Extra — not the Flatpak)
  zip                                        # 'gnome-extensions pack' needs it:
                                             # Gradia Capture is built from source
  gradia                                     # the *app* Gradia Capture annotates
                                             # into and OCRs with (Extra 1.13.0).
                                             # The extension is the pair to this
                                             # program, not a replacement for it;
                                             # Flathub be.alexandervanhee.gradia is
                                             # the same app if you prefer Flatpak.
)

# The managed set: what makes GNOME behave like the desktop this repo configures
# for, and what `ucli setup-extensions` installs on every machine. Bluefin's
# equivalent list is dash-to-dock, appindicator, gsconnect, blur-my-shell and
# search-light; the three at the end are "make it calm" tweaks that belong to the
# same opinion, not to one person.
#
# Names here describe WHERE an extension lands, not how much it is wanted:
#   GNOME_SYSTEM_EXTENSION_PACKAGES  pacman -> /usr/share/gnome-shell/extensions,
#                                    i.e. Extension Manager's "System Extensions"
#   GNOME_EXTENSION_TOOLING          not extensions at all: Extension Manager,
#                                    zip, and the Gradia app the capture
#                                    extension drives
#   GNOME_MANAGED_EXTENSIONS (this)   gext  -> ~/.local/share/gnome-shell/
#                                    extensions, i.e. the user list
#   PERSONAL_GNOME_EXTENSIONS         gext, from packages.local.bash, also the
#                                    user list, but yours instead of the repo's
# Only pacman can put an extension in the "system" section: gext installs per user
# by design, and hand-copying EGO zips into /usr/share as root would trade updates
# for a label.
#
# Two deliberate differences from Bluefin's list:
#   * search-light is gone. EGO's newest *active* release declares shell 48/49,
#     the 50 build was rejected, nothing covers 51, and GNOME disables what it
#     cannot load — it showed up in Extension Manager as a red error. Bluefin still
#     bakes it; here a dead entry in a managed set is worse than no entry.
#   * gradia-integration is added (see below), so the screenshot tool can annotate.
#
# Gradia Capture (gradia-integration@alexandervanhee.github.io) is in the set but
# NOT in this array: it is on neither extensions.gnome.org nor in the repos, so
# there is no PK to install from. install-gnome-extension-set.sh builds it from its
# pinned upstream commit (install-gradia-capture.sh) and enables it with the rest.
#
# What is deliberately NOT here, and why: copyous and gnome-ui-tune are "sometimes"
# extensions — installed on the machines that want them, from the overlay. The
# eight that stay are the ones installed on every GNOME setup: dash-to-dock,
# blur-my-shell, gsconnect, just-perfection, logo-menu, BetterTrayIcons,
# user-theme, plus appindicator and caffeine as system packages.
GNOME_MANAGED_EXTENSIONS=(
  "19:user-theme@gnome-shell-extensions.gcampax.github.com"  # shell themes from ~/.themes
                                                             # (firefox-gnome-theme styles the
                                                             # shell through this one)
  "307:dash-to-dock@micxgx.gmail.com"                        # Ubuntu-like dock
  "3193:blur-my-shell@aunetx"                                # blur behind shell UI
  "1319:gsconnect@andyholmes.github.io"                      # phone integration
  "3843:just-perfection-desktop@just-perfection"             # hide what GNOME shows by default
  "4451:logomenu@aryan_k"                                    # app-menu button
  "9975:BetterTrayIcons@nexaknight.com"                      # consistent tray icon sizes
)

# Personal extension sets, personal apps/flatpaks and extra dev packages live in
# ~/.config/ucli/packages.local.bash (see packages.local.bash.example). That file
# is never chezmoi-managed: it holds PERSONAL_GNOME_EXTENSIONS ("PK:UUID" too),
# PERSONAL_PKGS, PERSONAL_DEV and PERSONAL_FLATPAKS, and every installer reads it
# only if it exists.
#
# Empty defaults on purpose: the installers source the overlay *after* this file,
# `set -u` needs the names to exist, and the static check greps for them here.
PERSONAL_PKGS=()
PERSONAL_DEV=()
PERSONAL_FLATPAKS=()
PERSONAL_GNOME_EXTENSIONS=()

# ArchWiki: gnome-boxes, gdm-settings, nautilus-* are all optional — remove
# any you don't use to debloat your GNOME install.
# https://wiki.archlinux.org/title/GNOME
# The browser is desktop-agnostic, the terminal is not. Both are owned by the
# desktop step (`setup-desktop`/`ucli setup-system`) and repeated by `ucli apps`
# so a machine that skipped the desktop still gets them: Firefox carries the
# Betterfox user.js, the extension list and the GNOME theme, and the terminal is
# the one ~/.config/<terminal> is written for.
DESKTOP_BROWSER=(
  firefox
)

# GNOME: ghostty. GTK4 + native Wayland, so it lands in the Adwaita/Libadwaita
# stack GNOME already ships, and ~/.config/ghostty is the config this repo has.
DESKTOP_TERMINAL_GNOME=(
  ghostty
)

# Hyprland: ghostty as well, which is why `kitty` is no longer in
# DESKTOP_HYPRLAND_BASE. Ghostty is a first-class wlroots/Wayland client, honours
# Hyprland window rules, and one terminal config beats two. Swap this array for
# `kitty` if you use kitty's scripting/session features.
DESKTOP_TERMINAL_HYPRLAND=(
  ghostty
)

# KDE: kwi — the new KDE terminal (announced 2026-11-01): Qt Quick + Kirigami,
# GPU rendering through the Qt Scene Graph, and libghostty-vt underneath, so both
# ends of this repo now share Ghostty's terminal core. It is experimental and not
# in the Arch repos yet, so it resolves as the AUR package kwi-git (which provides
# `kwi`); if that is unavailable, Plasma still installs Konsole, so a KDE desktop
# always has a terminal. kitty is what this array said before kwi existed.
DESKTOP_TERMINAL_KDE=(
  kwi
)

GNOME_APP_OVERRIDES=(
  gnome-boxes            # VM manager
  nautilus-admin-gtk4    # Nautilus: open as admin
  nautilus-my-computer   # Nautilus: "My Computer" entry
  nautilus-open-any-terminal  # Nautilus: "Open in terminal"
)
# extension-manager used to live here, as one of `ucli apps`' GNOME extras. It is
# not an app extra: it is how you look at, enable and tune the extensions the
# desktop step installs, so it belongs to GNOME_SYSTEM_EXTENSION_PACKAGES and
# arrives with the desktop (and with `ucli setup-extensions`).

# ArchWiki: gnome-tweaks — "Allows adjusting advanced GNOME options"
# https://wiki.archlinux.org/title/GNOME#Advanced_settings

# ArchWiki: gdm is the display manager included in the gnome group.
# https://wiki.archlinux.org/title/GNOME#Starting
SERVICES_GNOME=(
  gdm
)

# -----------------------------
# Hyprland / KDE

# Hyprland essentials: compositor + notifications + launcher + portal + session
# tools. The terminal is not here: DESKTOP_TERMINAL_HYPRLAND picks it (ghostty).
# What a session needs to be usable is BASE; what is merely convenient is
# ADDITIONS, which `setup-desktop --choose` offers as separate toggles and which
# a distro-installed Hyprland still gets (`--additions-only`). The display
# manager is neither: it is SERVICES_HYPRLAND below, and setup-desktop /
# install-packages install and enable it from there.
# -----------------------------

DESKTOP_HYPRLAND_BASE=(
  hyprland
  dunst
  uwsm
  wofi
  xdg-desktop-portal-hyprland
  qt5-wayland
  qt6-wayland
  polkit-kde-agent
  wl-clipboard
)

DESKTOP_HYPRLAND_ADDITIONS=(
  dolphin      # file manager — remove if you use another
  grim         # screenshots (grim + slurp) — remove if you don't screenshot
  slurp
)

SERVICES_HYPRLAND=(
  sddm
)

# KDE essentials. The full `plasma` group brings the KDE application set that
# most people never open (see DESKTOP_SKIP_KDE below); the terminal comes from
# DESKTOP_TERMINAL_KDE. The two apps worth naming explicitly are ADDITIONS: on a
# distro-provided Plasma they are already there, on a bare one they come with
# `--additions-only` or `ucli setup-desktop --choose`.
DESKTOP_KDE_BASE=(
  plasma
  plasma-wayland-session
)

DESKTOP_KDE_ADDITIONS=(
  dolphin
  kate
)

SERVICES_KDE=(
  sddm
)

# -----------------------------
# Personal apps
# -----------------------------

# firefox lives in DESKTOP_BROWSER: it belongs to the desktop tier, not to the
# optional personal-apps step.
# Desktop apps, opinionated: system tooling (disks, snapshots, backups) and the
# pieces the desktop expects (Flatpak backend for shelly). Password managers,
# torrent clients and anything account-bound belong in PERSONAL_PKGS.
APPS=(
  btrfs-assistant
  gparted
  webapp-manager
  deja-dup
  fuse2
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

# Flatpak housekeeping only. Every other flatpak (Spotify, Obsidian, Bottles,
# Vesktop, the wallpaper/theme tools, …) is a personal pick and belongs in
# PERSONAL_FLATPAKS in packages.local.bash.
APP_FLATPAKS=(
  com.github.tchx84.Flatseal       # per-app sandbox permissions
  io.github.flattool.Warehouse     # install/manage/uninstall flatpaks
  io.github.flattool.Ignition      # installed-package overview
  io.github.giantpinkrobots.flatsweep  # remove unused runtimes
)

# GNOME-specific flatpaks. No AddWater: the GNOME theme is installed directly by
# firefox-gnome-theme. No MissionCenter: the pacman package arrives through the
# gnome-system-monitor= replace, so the flatpak would be a second copy.
GNOME_FLATPAKS=(
  io.github.nacho.mecalin
  io.gitlab.adhami3310.Impression   # ISO writer
)

HYPRLAND_FLATPAKS=()
KDE_FLATPAKS=()

DEV_FLATPAKS=(
  me.iepure.devtoolbox
  com.ranfdev.DistroShelf          # GUI over distrobox containers
)

GAMING_FLATPAKS=()
