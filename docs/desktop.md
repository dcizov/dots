# Desktop and GNOME

## Software replacement matrix

When installing a desktop environment, some packages from the DE group may be unwanted or have better alternatives. The matrix in `packages.bash` defines what to skip and what to replace:

| DE | Skip | Replace | With | Method |
|----|------|---------|------|--------|
| GNOME | none by default | `gnome-software` | `shelly` | AUR via `paru` (MANUAL_AUR) |
| GNOME | — | `gnome-system-monitor` | `mission-center` | Flatpak (`io.missioncenter.MissionCenter`) |
| GNOME | — | `gnome-console` | `ghostty` | Already chezmoi-managed |
| GNOME | — | `htop` | `btop` | `btop` in `SYSTEM_QOL_TOOLS` |
| Hyprland | none | — | — | — |
| KDE | none | — | — | — |

Edit `DESKTOP_SKIP_<DE>` and `DESKTOP_REPLACE_<DE>` in `packages.bash` to customize. The replacement runs automatically during `setup-desktop`.

### The terminal is chosen per desktop

`setup-desktop` installs firefox everywhere, and then one terminal:

| Desktop | Terminal array | Why |
|---|---|---|
| GNOME | `DESKTOP_TERMINAL_GNOME` → `ghostty` | GTK4 + native Wayland; GNOME already ships that stack, and `~/.config/ghostty` is the config in this repo |
| Hyprland | `DESKTOP_TERMINAL_HYPRLAND` → `ghostty` | first-class wlroots client that honours Hyprland window rules, so kitty is not installed as well |
| KDE | `DESKTOP_TERMINAL_KDE` → `kwi` | KDE's new terminal (2026-11-01): Qt Quick/Kirigami, Vulkan/OpenGL rendering through the Qt Scene Graph, libghostty-vt underneath — so both halves of this repo sit on Ghostty's terminal core. Experimental and AUR-only today (`kwi-git` provides `kwi`); Konsole comes with the `plasma` group, so the desktop always has a terminal |

A machine with no desktop installs neither. `~/.config/ghostty` / `~/.config/kitty` are only deployed once that binary exists, so a console install never carries a terminal config.

**Shelly** is an AUR package (Seafoam-Labs/Shelly-ALPM), installed via `paru`:
https://aur.archlinux.org/packages/shelly

## GNOME

```bash
ucli gnome                GNOME menu (extensions, settings backup, apply)
```

GNOME is curated in `packages.bash`. Package group contents from
[archlinux.org/groups/x86_64/gnome/](https://archlinux.org/groups/x86_64/gnome/).

## GNOME settings backup & restore

Back up your GNOME configuration after customizing it, then restore on reinstall:

```bash
# Backup (after configuring GNOME your way)
ucli backup-gnome-settings
# Saves to ~/.config/ucli/settings/gnome/ (chezmoi-managed)
#   desktop.dconf, shell.dconf, extensions.dconf
#   enabled-extensions.txt, installed-extensions.txt

# Restore (on a fresh install, after GNOME is installed)
ucli restore-gnome-settings
# Loads dconf settings + re-enables extensions
```

Commands to inspect your GNOME setup:

```bash
# List enabled extensions (installed + active)
gnome-extensions list --enabled

# List ALL installed extensions
gnome-extensions list

# List enabled via dconf (may include removed ones)
gsettings get org.gnome.shell enabled-extensions

# User-installed extensions
ls ~/.local/share/gnome-shell/extensions/

# System-wide installed extensions
ls /usr/share/gnome-shell/extensions/

# Backup ALL gsettings
dconf dump / > gnome-settings-backup.txt

# Restore ALL gsettings
dconf load / < gnome-settings-backup.txt
```

## chezmoi — adding your backed-up GNOME settings to the repo

The backup files live in `~/.config/ucli/settings/gnome/`. To deploy them via chezmoi:

```bash
chezmoi add ~/.config/ucli/settings/gnome/
chezmoi diff ~/.config/ucli/settings/gnome/
chezmoi apply
cd /home/user/dots
git add -A
git commit -m "chore: add GNOME settings backup templates"
git push origin arena/fc51c308-dots
```

**Note:** GNOME settings are personal (wallpaper, extension preferences, window behavior). If you deploy them via chezmoi, all machines sharing this repo get identical GNOME configuration. For machine-specific settings, don't `chezmoi add` them — keep them local and restore manually with `ucli restore-gnome-settings` per machine.
