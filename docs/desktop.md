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
ucli setup-extensions         extension packages + the managed sets, installed and enabled
ucli gnome-defaults           the curated settings: dock, blur, clock, hot corners, Nautilus
ucli gnome-defaults --status  what is set, what is yours, what is missing
ucli backup-gnome-settings    dconf + extension list -> ~/.local/share/ucli/settings/gnome
ucli restore-gnome-settings   put them back
```

GNOME is curated in `packages.bash`. Package group contents from
[archlinux.org/groups/x86_64/gnome/](https://archlinux.org/groups/x86_64/gnome/).

### Curated defaults, out of the box

Bluefin's "curated GNOME, out of the box" is one file: `zz0-bluefin-modifications.gschema.override`
in `/usr/share/glib-2.0/schemas`. It sets `org.gnome.shell enabled-extensions` as
a *schema default* (so every new user starts with the extensions on) and in the
same file tunes them and the shell — dock as a fixed bar with dots, popup blur,
`Super`-vs-`Alt`-Tab split, weekday in the clock, no hot corners, Adwaita fonts,
their accent. Locks live separately in `/etc/dconf/db/distro.d/locks/`.

`gnome-defaults.sh` applies the same kind of values, minus Bluefin's identity
(their fonts, wallpaper, stores) and plus this repo's choices (`ghostty`, the
Nautilus extensions):

| What | Where it shows |
|---|---|
| `:minimize,maximize,close`, center new windows, `Super`-Tab apps / `Alt`-Tab windows, `Super-D` desktop | window buttons, Alt-Tab behaviour |
| hot corners off, weekday clock, accent `slate`, numlock on, folders-first file choosers | the shell itself; `accent-color` is GNOME 47+ and is skipped on older shells |
| legacy apps: `gtk-theme = adw-gtk3-dark` (`adw-gtk-theme`, Extra 6.5) | every GTK3 app — GIMP, Inkscape, Thunar, the file dialogs inside them — instead of stock Adwaita |
| `favorite-apps`: firefox, ghostty, nautilus, settings, text editor | the dock on first login |
| dash-to-dock: fixed bar, 80 % dark background, dots indicators, no overview-on-startup | the dock |
| blur-my-shell: dash-to-dock + popup panels | the dock and menus |
| `nautilus-open-any-terminal`: `terminal=ghostty`, no keybinding, host binary (`flatpak=none`) | Nautilus right-click → Open in Terminal |

Why not the override file itself: it lives in a directory pacman owns and
`glib-compile-schemas` rewrites for the whole system — the distro's job, not
chezmoi's. Applied as *user* settings the result on a single-user machine is the
same, and it stays inspectable (`dconf dump /org/gnome/`) and reversible.

It is a default, not a lock — the rule is:

| Current value | What happens |
|---|---|
| equals the repo's value | nothing |
| equals the compiled schema default (i.e. you never touched it) | set it |
| anything else — you chose it | **kept**, reported as `keep … (yours)`; `ucli gnome-defaults --force` overwrites |

The schema default is read with `GSETTINGS_BACKEND=memory gsettings get`, i.e.
with a backend that has no user values, so no dconf-path guessing and no Python.
Keys whose schema is not installed are skipped and counted — dash-to-dock and
blur-my-shell only appear once the extension is there, `accent-color` only on
47+, `nautilus-open-any-terminal`'s schema only once that AUR package is in.

When it runs: after the extension sets in `ucli setup-system gnome` and in
`ucli setup-extensions`, and in `ucli apps` right after `GNOME_APP_OVERRIDES`
because that is the array the Nautilus extensions live in. `ucli apps --force`
passes nothing extra here on purpose: it must not reset settings you set by hand.
It ends with `nautilus -q` when Nautilus is open, because the file manager reads
its Python extensions at startup — that is the whole reason "I installed the
extension and the menu entry never appeared" happens.

### Legacy applications

libadwaita apps are styled by their own toolkit and need nothing. GTK3 apps — GIMP,
Inkscape, Thunar, most of the file dialogs — are not, so on a stock GNOME they look
a decade older than everything around them. `adw-gtk-theme` is
[lassekongo83/adw-gtk3](https://github.com/lassekongo83/adw-gtk3): libadwaita's
look ported to GTK3. The package ships `/usr/share/themes/adw-gtk3` and
`adw-gtk3-dark` — the package name and the theme names differ, which is why
searching the repos for `adw-gtk3` finds nothing.

It arrives with `FONTS_THEMES` (i.e. the `base` tier, before any desktop), and
`gnome-defaults` sets `org.gnome.desktop.interface gtk-theme` to **`adw-gtk3-dark`**
— the legacy half matches the dark libadwaita apps. That key carries a
`|/usr/share/themes/adw-gtk3-dark` requirement in the table, so a machine without
the package gets a `skip … needs …` line instead of a running order for a theme
that is not there.

### Flatpak: the theme as a runtime extension

A sandboxed app never reads `/usr/share/themes`, so "the GTK theme is set with
gsettings" is only half the job. GTK3 themes reach Flatpak as **runtime
extensions** named `org.gtk.Gtk3theme.<theme>`, and adw-gtk3 is packaged on
Flathub in both variants (`…adw-gtk3`, `…adw-gtk3-dark`, x86_64 + aarch64).

What the sources say:

* **Flatpak docs** ([Desktop Integration → Installing themes](https://docs.flatpak.org/en/latest/desktop-integration.html)): as of Flatpak 0.10.1 Flatpak detects the
  host's theme by reading the `gtk-theme` DConf key and, if a matching extension
  exists in the remote, **installs it automatically during `flatpak install` or
  `flatpak update`**.
* **adw-gtk3's README**: `flatpak install org.gtk.Gtk3theme.adw-gtk3
  org.gtk.Gtk3theme.adw-gtk3-dark`.
* **ArchWiki** (Flatpak → *applications not picking up the default system theme*):
  "the easiest solution is using themes that are available in Flathub", and the
  `flatpak override --filesystem=xdg-data/themes` route weakens the sandbox — `/usr`
  is never shared, so it needs the theme copied out of `/usr/share/themes` first.

So the repo does the supported thing explicitly, and gets it done *before* the first
Flatpak app runs instead of at some later `flatpak update`:

```bash
ucli flatpak-theme            # this user's Flatpak installation (default)
ucli flatpak-theme --system   # system-wide (root + system-wide apps)
ucli flatpak-theme --dry-run  # print the two flatpak commands
```

`install-flatpak-gtk-theme.sh` adds the flathub remote in that scope if it is
missing, installs whichever of the two extensions is absent, then **verifies** by
listing installed runtimes rather than trusting the exit code — and warns when the
host package is not there, since an extension with no host theme is themed on one
side only. It is idempotent (already installed → `already installed`), and runs
from `ucli apps` right after the Flatpaks step, and from `ucli setup-system gnome`
when flatpak is already present.

Two things it does **not** do, on purpose: it never `flatpak override`s your
sandbox, and it does not install the light theme instead of the dark one — both
extensions go in, so switching the host back to `adw-gtk3` needs no rerun.

The Flatpak theme is a GTK3 concern only: libadwaita apps (most GNOME apps) ignore
`gtk-theme` and follow the Settings portal's `color-scheme` instead, which the
sandbox already gets from the host.

The legacy switch is not the style switch: GNOME Settings → Appearance → *Style*
(light/dark) sets `color-scheme`, which styles libadwaita apps, while the GTK3
theme is the separate legacy entry (also in `gnome-tweaks` → *Appearance → Legacy
Applications*). This repo sets the legacy one to dark and leaves `color-scheme`
alone; `ucli gnome-defaults --force` puts it back if a Settings toggle overwrote it.

### Two extension sets, two sources

| | Where | Installed by |
|---|---|---|
| repo-packaged | `GNOME_SYSTEM_EXTENSION_PACKAGES`: `gnome-shell-extension-caffeine`, `gnome-shell-extension-appindicator` | `install-packages.sh essentials` — i.e. the desktop step — and `ucli setup-extensions` (`gnome-extensions` mode) |
| the tooling around them | `GNOME_EXTENSION_TOOLING`: **Extension Manager** (`extension-manager`, Extra 0.6.5), `zip` (source builds), **`gradia`** (the app Gradia Capture annotates into and OCRs with) | same two places — the desktop step and `gnome-extensions` mode |
| extensions.gnome.org | `GNOME_MANAGED_EXTENSIONS`, the repo's set, plus `PERSONAL_GNOME_EXTENSIONS` from the overlay | gext, on GNOME, in `setup-desktop` and `ucli setup-extensions` |

**Extension Manager** is part of that package set on purpose. Before it, this was
in `GNOME_APP_OVERRIDES`, i.e. `ucli apps`: you could have extensions installed and
enabled by the desktop step with no GUI to look at them, tune their settings or
switch one off, until you ran a later tier. Installing extensions and installing
the tool that manages them are the same job, so they ship together (pacman
`extension-manager`, not the Flathub build, and `ucli debloat-desktop` can still
remove it because the extension packages are among its candidates).

Extension Manager calls these two rows two different things, and the difference is
only the directory: pacman's go to `/usr/share/gnome-shell/extensions` (**System
Extensions**), gext's to `~/.local/share/gnome-shell/extensions` (the user list).
That is why exactly two entries show up as system extensions here and eight as
user ones.

"User" and "system" are therefore not a preference — they are *who installs it*.
Only pacman can put an extension in `/usr/share`: gext installs per user by design,
and hand-copying EGO zips into `/usr/share` as root would buy the label at the cost
of updates (gext cannot see or update them), root-owned files in `ucli uninstall`,
and system-wide schema compilation. The preference that *does* exist is the one the
arrays encode: installed on every machine (`GNOME_MANAGED_EXTENSIONS` +
`GNOME_SYSTEM_EXTENSION_PACKAGES`) versus installed on the machines that ask for it
(`PERSONAL_GNOME_EXTENSIONS` in the overlay). `GNOME_EXTENSION_TOOLING` is neither
an extension nor a preference: it is what the extension step needs to work —
the GUI, `zip`, and the Gradia app.

`gnome-shell-extensions` is deliberately **not** installed. It is one package
carrying fourteen classic extensions (apps-menu, auto-move-windows, drive-menu,
launch-new-instance, light-style, native-window-placement, places-menu,
screenshot-window-sizer, status-icons, system-monitor, `user-theme`, window-list,
windowsNavigator, workspace-indicator) — of which this repo needs one, and only
for `user-theme`, which arrived *disabled* because nothing enabled it. `user-theme`
is PK 19 on extensions.gnome.org (upstream GNOME, fmuellner), so it is now part of
the managed set below: installed **and** enabled, and the other thirteen never
appear. Machines set up before that change still have the package; the set script
says so and prints `sudo pacman -Rns gnome-shell-extensions`.

The managed set is deliberately small — eight extensions, seven of them from
extensions.gnome.org:

| PK | UUID | Why |
|---|---|---|
| 19 | `user-theme@gnome-shell-extensions.gcampax.github.com` | shell themes from `~/.themes`; what firefox-gnome-theme needs. Used to ride in on `gnome-shell-extensions` |
| 307 | `dash-to-dock@micxgx.gmail.com` | Ubuntu-like dock |
| 3193 | `blur-my-shell@aunetx` | blur behind shell UI |
| 1319 | `gsconnect@andyholmes.github.io` | phone integration (KDE Connect protocol) |
| 3843 | `just-perfection-desktop@just-perfection` | hide the shell furniture GNOME shows by default |
| 4451 | `logomenu@aryan_k` | app-menu button in the panel |
| 9975 | `BetterTrayIcons@nexaknight.com` | consistent tray icon sizes |
| — | `gradia-integration@alexandervanhee.github.io` | annotations/OCR for the built-in screenshot tool. **Built from source** — no EGO listing, no Arch *extension* package (the *app* it drives is `gradia` in Extra, installed as tooling) |

#### Gradia Capture, the one entry with no PK

`gradia-integration@alexandervanhee.github.io` (Alexander Vanhee, the Gradia app
author; metadata declares shell 49/50/51) exists only as source in
[AlexanderVanhee/gradia-capture](https://github.com/AlexanderVanhee/gradia-capture).
Extensions.gnome.org has no such UUID (checked 2026-11-05 via the EGO query API),
Arch's `gradia` package ships the *app* only — the pair to the extension, not a
container for it — so `gext install` has nothing to fetch. The app is installed
as tooling (`GNOME_EXTENSION_TOOLING`); an extension without its app annotates
into the clipboard and has no OCR.

Bluefin solves that by building the extension into the image with the project's
own `build.sh`; `install-gradia-capture.sh` does the same thing per user at setup
time: fetch the **pinned commit** (`git fetch --depth 1 <sha>`, not a branch —
this runs `gnome-extensions pack` and installs what comes out), run `build.sh`,
`gnome-extensions install --force` the resulting zip into
`~/.local/share/gnome-shell/extensions/`, and leave enabling to the one
`enabled-extensions` write. Dependencies: `zip` (in
`GNOME_EXTENSION_TOOLING`), `git`, and the `gnome-extensions` CLI from
`gnome-shell`. Gated on the commit (`gnome-gradia-capture`), and it re-checks the
extension directory, so a wiped `~/.local` rebuilds instead of skipping. A build
failure makes the set report incomplete — it is part of the set, not a footnote.

The annotated screenshot lands in the clipboard / Gradia app; OCR needs Gradia
itself, which is why `gradia` is installed with the desktop step. Prefer the
Flathub build (`be.alexandervanhee.gradia`)? `ucli` will not fight you for it, but
it is the same program — there is no extension-only setup worth having.

**Search Light is gone** (`5489`). EGO's newest *active* release declares shell
48/49, the 50 build was rejected, nothing covers 51 — GNOME refuses to load it and
Extension Manager shows a red error next to a toggle that will not stay on. Bluefin
still bakes it in; a dead entry in a managed set is worse than no entry.

Each entry is `"PK:UUID"` on one line: PK is what `gext install` takes, UUID is
what GNOME enables. They used to be two parallel arrays, and they drifted badly —
the list installed Search Light while enabling GSConnect, whose PK is 1319 (the
list claimed that was AppIndicator support, actually 615). One line per extension
cannot drift. Gradia Capture is the exception that needs a second mechanism rather
than a second list: `install-gnome-extension-set.sh` adds its UUID to the same
single `enabled-extensions` write, so a broken build shows up as an incomplete set
instead of an extension that is enabled but absent.

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
the `personal` set (`ucli setup-extensions` runs both). This is where "sometimes"
extensions live — worth having on some machines and not on others:

| PK | UUID | Why it is not in the repo's set |
|---|---|---|
| 10070 | `user-accent-colors@fabito02` | accent colour per app: taste |
| 8834 | `copyous@boerdereinar.dev` | clipboard history; needs `libgda6` + `gsound` (the example lists them in `PERSONAL_PKGS`) |
| 4158 | `gnome-ui-tune@itstime.tech` | overview tweaks: nice on a big screen, noise on a laptop |

The overlay is copied by hand (`cp …/packages.local.bash.example …/packages.local.bash`)
and never chezmoi-managed, so a fresh machine gets only the repo's eight plus the
two system packages — `ucli setup-extensions` installs the overlay's entries only
if you created that file. Deleting an entry *does* uninstall it now: see below.

#### Removing or moving an extension

One rule: **edit the arrays, then re-run the step.** The set owns what it put
there, so it also removes it:

| You want | Do |
|---|---|
| remove an extension | delete its `"PK:UUID"` line from `GNOME_MANAGED_EXTENSIONS`, or from the overlay's `PERSONAL_GNOME_EXTENSIONS` |
| move it between the repo set and your overlay | delete the line from one array, add the identical `"PK:UUID"` line to the other — one edit, then one run |
| keep it, but not under `ucli`'s control | delete the line, run `ucli setup-extensions`, then install it yourself from Extension Manager |

then `ucli setup-extensions` (add `--force` if nothing else in the set changed and
you want everything re-applied; the prune does not need it, it runs before the
gate).

How it decides what to remove: the script records the UUIDs it installed in
`~/.local/state/ucli/gnome-extensions.installed`, one per line. Every run — both
modes, before the gate and before anything is installed — subtracts the wanted
set from that manifest and handles each dropped UUID:

1. remove it from `org.gnome.shell enabled-extensions` (the same single write that
   enabling uses, so you never get a half-written list), then
2. `gnome-extensions uninstall` it, if it lives in
   `~/.local/share/gnome-shell/extensions`;
3. if it only exists in `/usr/share/gnome-shell/extensions`, **disable it** and say
   so — those files are pacman's (`pacman -Q` shows the package), and a script
   silently removing packages is worse than leaving a disabled extension;
4. if the directory is already gone, still drop the stale enabled entry.

The wanted set is the *union* of `GNOME_MANAGED_EXTENSIONS`,
`PERSONAL_GNOME_EXTENSIONS` and Gradia Capture — so `ucli setup-extensions`
running `managed` and then `personal` never removes the other mode's extensions,
and moving an entry between the two arrays is a no-op for the prune. Gradia has
no PK line to delete; it follows the managed array, so it leaves with it.

**Extensions you installed yourself are never touched.** They were never in the
manifest, so the subtraction cannot reach them. That is the entire reason for the
manifest: `enabled-extensions` alone cannot distinguish "dropped from the array"
from "the user wanted this", and guessing from a diff is how a setup script
deletes someone's work. `rm ~/.local/state/ucli/gnome-extensions.installed` gives
up ownership — the next run records what it installs and prunes nothing.

Two consequences worth knowing: the manifest is only written when the set is
*complete* (a half-installed set does not claim ownership of what failed, and
only UUIDs that are really installed are recorded), and emptying the array
retires the whole set instead of erroring — `GNOME_MANAGED_EXTENSIONS=()` plus
one run removes all eight and Gradia Capture, leaving your own extensions and
the overlay's alone.

#### How Bluefin does it, and why this repo does not copy that

Bluefin bakes extensions into the image: the extension directories ship in
`/usr/share/gnome-shell/extensions` (some packaged as RPMs from their own COPR,
some built at image build time), enabled through a **compiled GSettings default**
in `/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override`
(`[org.gnome.shell] enabled-extensions = [...]`), with per-extension settings in
`/etc/dconf/db/distro.d/` keyfiles rebuilt by `dconf-update.service`, and
hardware-specific bits applied per user by `ublue-user-setup.service`.

What that means in Extension Manager: **everything Bluefin ships is under "System
Extensions", and their user list is empty** until you install something from
extensions.gnome.org yourself. Their inventory (current `main`: the directories in
`system_files/shared/usr/share/gnome-shell/extensions`, built by
`build_files/shared/build-gnome-extensions.sh`):

| Bluefin extension | How it gets there | Here |
|---|---|---|
| `appindicatorsupport@rgcjonas.gmail.com` | unpacked into the image, schemas compiled at build | same, but from pacman (`gnome-shell-extension-appindicator`) |
| `blur-my-shell@aunetx` | `make` + unpack the extension zip in the build | same, gext (PK 3193) |
| `dash-to-dock@micxgx.gmail.com` | same (`make` + `glib-compile-schemas`) | same, gext (PK 307) |
| `caffeine@patapon.info` | `gnome-extensions pack` (gettext catalogues) + unpack | same, but from pacman |
| `gsconnect@andyholmes.github.io` | `meson setup` + `meson install` | same, gext (PK 1319) |
| `logomenu@aryan_k` | unpacked, plus its `distroshelf-helper`/`missioncenter-helper` binaries into `/usr/bin` | same, gext (PK 4451) — its helper binaries then have to exist some other way, see below |
| `search-light@icedman.github.com` | unpacked, schemas compiled | **dropped** — dead on shell 50/51 |
| `gradia-integration@alexandervanhee.github.io` | built by the extension's own `build.sh` | **same**, built per user from the same pinned commit |
| `bazaar-integration@kolunmi.github.io` | unpacked | **not wanted** — it is the Bazaar app-store companion; no Bazaar here |
| — user list — | **nothing**: no gext, no per-user installs, so the section stays empty | nine gext extensions + Gradia Capture |

The delta in one line: **shared** — appindicator, caffeine, dash-to-dock,
blur-my-shell, gsconnect, logo-menu, gradia-integration. **Theirs only** —
search-light (dead on 50/51, so dropped here) and bazaar-integration (their
app-store companion; not wanted). **Here only** — user-theme (shell themes for
firefox-gnome-theme), just-perfection, BetterTrayIcons (copyous and gnome-ui-tune
live in the overlay now, not in the repo's set).
Both of theirs that are missing here come from the same cause: an image ships one
fixed list it rebuilds per GNOME release, so a stale entry survives until someone
touches the build. They pay a rebuild per release inside their pipeline (their
issue tracker shows what happens when that lags — "GNOME System Extensions are old,
unsupported for GNOME 50"); we fetch the current EGO release per user, at the cost
of a network call on the first run and a `gext` dependency — and gradia is the one
place where that model needs a build step anyway.

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
there, never replaces; the only thing that ever *removes* an entry from that list
is the prune, and only for extensions the manifest says this repo installed). gschema overrides and `distro.d` remain the right tool if
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
