# Installing

## Fresh install on Arch minimal

New to the repo? Read [getting-started](getting-started.md) first — it is the
same pipeline with what each step installs and how to configure it. This page is
the reference.

The pipeline, in order. Every step is idempotent and every step is also
runnable on its own (`setup-desktop`, `setup-extensions`, `apps`), so you
can stop in between, inspect, and continue.

```bash
# 0. archinstall (minimal profile), reboot, log in to the console

# 1. bootstrap: git, chezmoi, just — then the ucli runtime only
curl -fsSL https://raw.githubusercontent.com/dcizov/dots/main/install.sh | bash -s -- --yes
#    flags: --yes / --dry-run / --no-apply / --no-snapshot
#    deploys ~/.local/bin/ucli, ~/.config/ucli, ~/.local/share/ucli
#    and a ~/.bash_profile that puts ~/.local/bin on PATH. Nothing else.

# 2. snapshots, so everything after this point is reversible
ucli setup-snapshots        # snapper + limine, creates snapshot #1
ucli snapshot               # optional extra "clean machine" snapshot
#    --no-snapshot (or UCLI_NO_SNAPSHOT=1) configures/installs without snapshotting

# 3. the machine: base packages + the desktop you want
ucli setup-system gnome     # gnome | kde | hyprland
#    = bootstrap, cpu/gpu, system tools, fonts, ucli runtime
#    + DE with the replacement matrix
#    + firefox and that desktop's terminal (ghostty / kwi)
#    + the shell tier (zsh, oh-my-zsh, plugins, starship, chsh)
#    + chezmoi apply (now that those programs exist: ~/.zshrc, starship,
#      ~/.config/ghostty, ~/.config/ucli/firefox) 
#    + GNOME extensions (if gnome) + a "<DE> Setup" snapshot
#    + quiet boot: plymouth, and KERNEL_CMDLINE_EXTRA appended to limine
#      (standalone: ucli setup-boot [--dry-run] [--no-plymouth])

# 4. optional: drop DE packages you never use.
#    Takes a Snapper snapshot first (--no-snapshot skips it).
ucli debloat-desktop

# 5. extensions only (gnome) — same work step 3 did, rerunnable
ucli setup-extensions

# 6. the shell cosmetics: eza, bat, zoxide, atuin, tealdeer, glow, fzf
ucli cli

# 7. the apps: flatpaks, AUR, pacman, Firefox config
ucli apps

# 8. optional: developer stack
ucli devmode
```

Two epochs, on purpose. Before step 3 the machine is a console: `ucli` and a
`PATH`, nothing else — no zsh, no starship, no terminal or browser config. That
is what makes the fresh-install snapshot worth keeping. The dotfiles that need a
program (`~/.zshrc`, `~/.config/zsh`, `~/.config/starship.toml`,
`~/.config/ghostty`, `~/.config/kitty`, `~/.config/ucli/firefox`) are held back by
`.chezmoiignore`, which asks `lookPath` on every apply — so they appear the
moment the program does, and never before. A plain `chezmoi apply -v` on a
console box therefore deploys the same small set as the bootstrap.

| Terminal | Desktop | Why |
|---|---|---|
| ghostty | GNOME, Hyprland | GTK4 + native Wayland; already in the Adwaita stack GNOME ships, first-class wlroots client on Hyprland |
| kwi | KDE Plasma | KDE's new terminal: Qt Quick + Kirigami, GPU rendering via the Qt Scene Graph, libghostty-vt underneath. Experimental and AUR-only today (`kwi-git`); Konsole ships with the `plasma` group as the fallback |

Flip `DESKTOP_TERMINAL_KDE` / `DESKTOP_TERMINAL_HYPRLAND` in `packages.bash` if
you want it the other way round (kitty is still a perfectly good answer; its AUR
name is what makes `kwi` awkward today).

`ucli setup-system` asks before continuing when there is no Snapper config (it
proceeds unattended on a pipe or with `UCLI_YES=1`) — the desktop step is the
destructive one. `ucli debloat-desktop` and `ucli uninstall` take a snapshot
before they remove anything, for the same reason.

What each layer actually puts on disk:

| Layer | Comes from | Contents |
|---|---|---|
| bootstrap | `install.sh` | `~/.local/bin/ucli`, `~/.config/ucli`, `~/.local/share/ucli`, `~/.bash_profile` (`~/.local/bin` on PATH) |
| dotfiles | `chezmoi apply` | `~/.zshrc`, `~/.config/zsh/plugins.txt` (the one plugin list), `~/.config/zsh/conf.d/*` (aliases, functions, fzf, prompt), `~/.config/starship.toml`, `~/.config/ghostty` or `~/.config/kitty`, `~/.config/ucli/firefox` (copied into every Firefox profile) |
| system | `ucli setup-system` | bootstrap (git, chezmoi, just, zsh), cpu/gpu, system tools + `fwupd`, multimedia codecs, hardware-detected extras (`fprintd`, `libinput-tools`), fonts, gum + pipx |
| desktop | `ucli setup-system` → `setup-desktop.sh` | DE package set with skip/replace matrix, **firefox**, **ghostty** (gnome/hyprland) or **kwi** (kde), the repo-packaged GNOME extensions + the layout set, `chezmoi apply`, the Firefox profile (Betterfox `user.js` + GNOME theme), then a snapshot |
| shell | `ucli setup-system` → `setup-desktop.sh`, or `ucli cli` | zsh, oh-my-zsh, 4 plugin clones into `$ZSH_CUSTOM/plugins`, **starship**, `chsh -s zsh` |
| cosmetics | `ucli cli` | eza, bat, zoxide, atuin, tealdeer, glow, fzf |
| apps | `ucli apps` | `APPS` (pacman) + `APP_FLATPAKS` (flatpak) + `MANUAL_AUR` (shelly) + your `PERSONAL_*` overlay + the Firefox extension lists (written as `/etc/firefox/policies/policies.json`) + the personal GNOME extension set. The Firefox *profile* (Betterfox, GNOME theme) belongs to the browser: the desktop step installs it, and `ucli apps` calls the same script so it still works when Firefox is installed from here |
| dev | `ucli devmode` | `DEV_CLI` plumbing + `DEV` stack + dev box |

`ucli cli` on top of a plain zsh: oh-my-zsh + plugins + starship is the standard
setup (installed by `install-shell.sh`, which the desktop step also runs), and
the ucli layer rides on it through `plugins=()` and `~/.config/zsh/conf.d/*`
(deployed by chezmoi, so `ucli chezmoi-apply` refreshes it). Nothing in that
layer is ucli-specific magic — the same files work in the dev box.

On **CachyOS**, skip steps 2–5 — Calamares already did DE + Snapper/Limine
([docs/distros.md](distros.md) has the ownership and repository differences):

```bash
chezmoi init --apply https://github.com/dcizov/dots.git
ucli cli                     # shell tier (optional)
ucli apps                    # apps, flatpaks, Firefox config (firefox always, terminal when the DE is known)
ucli devmode                 # optional
```

## Running the bootstrap (no project domain)

`install.wtfaq.tech` is retired; the script lives in the repo and you can fetch it
straight from GitHub. All four methods run the same file:

```bash
# 1. pipe to bash — always the main branch
curl -fsSL https://raw.githubusercontent.com/dcizov/dots/main/install.sh | bash -s -- --yes

# 2. download, read, then run (recommended: it installs packages and runs as you)
curl -fsSLO https://raw.githubusercontent.com/dcizov/dots/main/install.sh
less install.sh && bash install.sh

# 3. from a clone — the way to run a branch or a fork
git clone https://github.com/dcizov/dots.git && cd dots && ./install.sh
./install.sh --branch my-branch --repo https://github.com/me/dots.git

# 4. tarball, no history
curl -fsSL https://codeload.github.com/dcizov/dots/tar.gz/refs/heads/main | tar xz
cd dots-main && ./install.sh
```

`--branch` only picks the branch `chezmoi init` uses; the download URLs above are
static, so to bootstrap from a non-main branch use method 3 or 4 (or point
`--repo`/`--branch` at it). The bootstrap never needs root until it installs
`git`/`chezmoi`/`just` with `pacman`, and it asks before doing that.

## Snapshots: one script, one switch

Every restore point in this repo is `scripts/system/snapshot-fresh-install.sh`,
called by the bootstrap, `ucli setup-system`, `ucli setup-desktop`,
`ucli setup-snapshots`, `ucli debloat-desktop`, `ucli uninstall` and by hand:

```bash
ucli snapshot                          # "Fresh Arch Linux Installation"
ucli snapshot "before the upgrade"     # your own description
ucli snapshot --dry-run                # show what would run
```

It skips itself, loudly but with exit 0, when there is nothing to snapshot (no
`snapper`, no `/etc/snapper/configs/root`, root not btrfs) — "not applicable" is
not "failed", and no step should die over a missing restore point. A real snapper
error still exits non-zero.

To turn snapshots off for a whole run, one switch reaches all of them:

```bash
ucli setup-system gnome --no-snapshot      # also skips the "<DE> Setup" snapshot
sudo UCLI_NO_SNAPSHOT=1 ...                # via sudo -E, or
ucli setup-snapshots --no-snapshot         # configure snapper, take no snapshot
ucli debloat-desktop --no-snapshot
ucli uninstall --no-snapshot
```

## Snapshot-only path (skip chezmoi initially)

If you want to create a fresh-install snapshot **before** deploying dotfiles (e.g. right after archinstall, before `chezmoi apply`), you can run the snapshot setup directly without chezmoi:

```bash
# After archinstall + reboot, as root:
sudo arch-snapper-limine.sh --yes

# This sets up Snapper (Btrfs subvolume check, config, timers),
# configures mkinitcpio hooks + Limine, and creates snapshot #1
# ("Fresh Arch Linux Installation").
```

If snapper is already configured (`/etc/snapper/configs/root` exists), you can create just the snapshot:

```bash
sudo snapshot-fresh-install.sh "Fresh Arch Install"
```

Scripts live in `~/.local/share/ucli/scripts/system/` after chezmoi deploy, or can be run directly from the repo before chezmoi apply.

**Snapshot-only flow:**

```bash
# 1. archinstall, reboot
# 2. Create snapshot before anything else touches the disk
sudo arch-snapper-limine.sh --yes

# 3. Then bootstrap: this only adds ucli + ~/.bash_profile PATH, so the
#    snapshot still describes a nearly-stock Arch install.
curl -fsSL https://raw.githubusercontent.com/dcizov/dots/main/install.sh | bash

# 4. Continue with ucli:
ucli setup-snapshots      # if you did not run arch-snapper-limine.sh above
ucli setup-system gnome   # DE + terminal + firefox + shell + dotfiles + snapshot
ucli cli
ucli devmode
ucli apps
```

Because the bootstrap no longer deploys the shell, terminal or browser config,
running it before or after the snapshot makes no real difference — nothing
desktop-shaped lands in `$HOME` until step 4.

## Arch system setup

```bash
ucli setup-snapshots      snapshots + boot entries (skips CachyOS)
ucli system               OS, CPU, disk and firmware facts
ucli setup-desktop        install DE + snapshot (Arch minimal only)
ucli debloat-desktop      remove DE packages you don't need
ucli backup-gnome-settings  backup dconf settings + extensions
ucli restore-gnome-settings # restore dconf settings + extensions
```

The Snapper/Limine script skips CachyOS.

## Fresh install readiness

| Step | Status |
|------|--------|
| Bootstrap (install.sh, `--dry-run`, `--yes`, no `-Syu`) | ✅ |
| chezmoi deployment (`.chezmoiignore` gates by terminal/role) | ✅ |
| DE install with package selection (`setup-desktop --choose`) | ✅ |
| DE debloat after install (`debloat-desktop`) | ✅ |
| Snapper/Limine setup (`setup-snapshots`, skips CachyOS) | ✅ |
| Fresh install snapshot (`snapshot-fresh-install.sh`) | ✅ |
| GNOME settings backup (`backup-gnome-settings`) | ✅ |
| GNOME settings restore (`restore-gnome-settings`) | ✅ |
| Dev packages (`devmode`, `--force` bypasses role check) | ✅ |
| Personal apps (`apps`) | ✅ |
| Software replacement matrix (skip + replace DE packages) | ✅ |
| All scripts pass `bash -n` | ✅ |
| All committed & pushed to `arena/fc51c308-dots` | ✅ |

On **Arch minimal**, run the full flow after first console login. On **CachyOS**, Calamares handles DE + Snapper/Limine during install — just deploy dotfiles and run `ucli` commands.
