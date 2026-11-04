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

`setup-desktop` installs firefox everywhere — and configures it in the same
step: a profile is created headlessly, the Betterfox `user.js` is copied in, and
on GNOME firefox-gnome-theme is installed, all before the `<DE> Setup` snapshot.
`ucli apps` only adds the extension list and calls the same script. Then one
terminal:

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
ucli setup-extensions     extension packages + the managed sets, installed and enabled
ucli backup-gnome-settings    dconf + extension list -> ~/.local/share/ucli/settings/gnome
ucli restore-gnome-settings   put them back
```

GNOME is curated in `packages.bash`. Package group contents from
[archlinux.org/groups/x86_64/gnome/](https://archlinux.org/groups/x86_64/gnome/).

### Two extension sets, two sources

| | Where | Installed by |
|---|---|---|
| repo-packaged | `GNOME_SYSTEM_EXTENSION_PACKAGES`: `gnome-shell-extensions` (carries `user-theme`, which the Firefox GNOME theme styles the shell through), `gnome-shell-extension-caffeine`, `gnome-shell-extension-appindicator`, plus **Extension Manager** (`extension-manager`, Extra 0.6.5) and Copyous' `libgda6`/`gsound` | `install-packages.sh essentials` — i.e. the desktop step — and `ucli setup-extensions` (`gnome-extensions` mode) |
| extensions.gnome.org | `GNOME_SYSTEM_EXTENSIONS`, the opinionated layout set | gext, on GNOME, in `setup-desktop` and `ucli setup-extensions` |

**Extension Manager** is part of that package set on purpose. Before it, this was
in `GNOME_APP_OVERRIDES`, i.e. `ucli apps`: you could have extensions installed and
enabled by the desktop step with no GUI to look at them, tune their settings or
switch one off, until you ran a later tier. Installing extensions and installing
the tool that manages them are the same job, so they ship together (pacman
`extension-manager`, not the Flathub build, and `ucli debloat-desktop` can still
remove it because the extension packages are among its candidates).

The layout set is deliberately small — five extensions, the same five Bluefin
ships a variation of:

| PK | UUID | Why |
|---|---|---|
| 307 | `dash-to-dock@micxgx.gmail.com` | Ubuntu-like dock |
| 3193 | `blur-my-shell@aunetx` | blur behind shell UI |
| 1319 | `gsconnect@andyholmes.github.io` | phone integration (KDE Connect protocol) |
| 5489 | `search-light@icedman.github.com` | Spotlight-style launcher on Super+Space |
| 8834 | `copyous@boerdereinar.dev` | clipboard history (needs `libgda6` + `gsound`) |
| 3843 | `just-perfection-desktop@just-perfection` | hide the shell furniture GNOME shows by default |
| 4451 | `logomenu@aryan_k` | app-menu button in the panel |
| 4158 | `gnome-ui-tune@itstime.tech` | overview tweaks |
| 9975 | `BetterTrayIcons@nexaknight.com` | consistent tray icon sizes |

Each entry is `"PK:UUID"` on one line: PK is what `gext install` takes, UUID is
what GNOME enables. They used to be two parallel arrays, and they drifted badly —
the list installed Search Light while enabling GSConnect, whose PK is 1319 (the
list claimed that was AppIndicator support, actually 615). One line per extension
cannot drift.

#### "Recorded as done" is not "done"

The set script checks the real state before it writes its gate, and it writes
nothing unless **every** extension in the set is installed *and* enabled:

- the gate is a fast path, not the truth — when it matches, `gext list` and
  `dconf read /org/gnome/shell/enabled-extensions` are still consulted, and a set
  that is not actually there is re-applied instead of skipped;
- a failed `gext install` prints gext's own error, keeps the UUID out of
  `enabled-extensions` (an extension GNOME cannot load is worse than a missing
  one), and exits non-zero, so `setup-extensions` and `setup-desktop` both say the
  set is incomplete and name the retry;
- an extension GNOME *disabled* (shell upgrade, Extension Manager, a first login
  before gext finished) counts as incomplete and gets enabled again.

So "no extensions after `ucli setup-system gnome`" is now a message, not silence:
`ucli setup-extensions` (as your user, not `sudo`) repairs it. `gext` itself is a
pipx package — `ucli install-gnome-extensions-cli` — and `~/.local/bin` is on
`PATH` from the zsh config, which is why the retry belongs in your shell.

#### The personal set

`PERSONAL_GNOME_EXTENSIONS` in `~/.config/ucli/packages.local.bash`, installed by
the `personal` set (`ucli setup-extensions` runs both). The example ships one
entry — `user-accent-colors` — because the rest of the taste set is opinionated
and already lives in the table above.

#### How Bluefin does it, and why this repo does not copy that

Bluefin bakes extensions into the image: the extension directories ship in
`/usr/share/gnome-shell/extensions` (some packaged as RPMs from their own COPR,
some built at image build time), enabled through a **compiled GSettings default**
in `/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override`
(`[org.gnome.shell] enabled-extensions = [...]`), with per-extension settings in
`/etc/dconf/db/distro.d/` keyfiles rebuilt by `dconf-update.service`, and
hardware-specific bits applied per user by `ublue-user-setup.service`.

That is a *system-wide default*, and it has a documented failure mode inside
Bluefin itself: the moment a user toggles anything in Extension Manager, a
user-level `enabled-extensions` value exists, and user values beat schema
defaults — so the image's list silently stops applying. The Arch/ucli equivalent
would also mean root-owned files that `ucli uninstall` has to clean up, for a
tool that runs as one user after the fact.

So this repo keeps the split: **packages** where Arch packages the extension
(`GNOME_SYSTEM_EXTENSION_PACKAGES`, installed with the desktop), and **one merged
dconf write** to the user's own `org.gnome.shell enabled-extensions` for the rest
(`enable_uuids` in `install-gnome-extension-set.sh` — it appends to whatever is
there, never replaces). gschema overrides and `distro.d` remain the right tool if
you ever turn this into a multi-user image; on a single-user post-install they
only add a second place where the truth can drift.

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
