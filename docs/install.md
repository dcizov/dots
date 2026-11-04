# Installing

## Fresh install on Arch minimal

The pipeline, in order. Every step is idempotent and every step is also
runnable on its own (`setup-desktop`, `setup-extensions`, `setup-apps`), so you
can stop in between, inspect, and continue.

```bash
# 0. archinstall (minimal profile), reboot, log in to the console

# 1. bootstrap chezmoi/ucli
curl -fsSL https://install.wtfaq.tech | bash   # --yes / --dry-run

# 2. deploy dotfiles
chezmoi apply -v

# 3. snapshots first, so everything after this point is reversible
ucli setup-snapshots        # snapper + limine, creates snapshot #1
ucli snapshot               # optional extra "clean machine" snapshot

# 4. the machine: base packages + the desktop you want
ucli setup-system gnome     # gnome | kde | hyprland
#    = bootstrap, cpu/gpu, system tools, fonts, ucli runtime
#    + DE with the replacement matrix + ghostty + firefox
#    + GNOME extensions (if gnome) + a "<DE> Setup" snapshot

# 5. optional: drop DE packages you never use.
#    Takes a Snapper snapshot first (--no-snapshot skips it).
ucli debloat-desktop

# 6. extensions only (gnome) — same work step 4 did, rerunnable
ucli setup-extensions

# 7. the shell: stock zsh + the ucli layer
ucli cli

# 8. the apps: flatpaks, AUR, pacman, Firefox config
ucli apps

# 9. optional: developer stack
ucli devmode
```

`ucli setup-system` asks before continuing when there is no Snapper config (it
proceeds unattended on a pipe or with `UCLI_YES=1`) — the desktop step is the
destructive one. `ucli debloat-desktop` and `ucli uninstall` take a snapshot
before they remove anything, for the same reason.

What each layer actually puts on disk:

| Layer | Comes from | Contents |
|---|---|---|
| dotfiles | `chezmoi apply` | `~/.zshrc`, `~/.config/zsh/plugins.txt` (the one plugin list), `~/.config/zsh/conf.d/*` (aliases, functions, fzf, prompt), `~/.config/starship.toml`, `~/.config/ghostty`, `~/.config/mozilla` |
| system | `ucli setup-system` | bootstrap (git, chezmoi, just, zsh), cpu/gpu, system tools, fonts, gum + pipx |
| desktop | `ucli setup-system` → `setup-desktop.sh` | DE package set with skip/replace matrix, **ghostty**, **firefox**, GNOME extension set, snapshot |
| shell | `ucli setup-system` → `setup-desktop.sh`, or `ucli cli` | zsh, oh-my-zsh, 4 plugin clones into `$ZSH_CUSTOM/plugins`, **starship**, `chsh -s zsh` |
| cosmetics | `ucli cli` | eza, bat, zoxide, atuin, tealdeer, glow, fzf |
| apps | `ucli apps` | `APPS` (pacman) + `APP_FLATPAKS` (flatpak) + `MANUAL_AUR` (shelly) + a headless first run of Firefox if it has no profile yet, then Betterfox `user.js`, the extension list and the Firefox GNOME theme |
| dev | `ucli devmode` | `DEV_CLI` plumbing + `DEV` stack + dev box |

`ucli cli` on top of a plain zsh: oh-my-zsh + plugins + starship is the standard
setup (installed by `install-shell.sh`, which the desktop step also runs), and
the ucli layer rides on it through `plugins=()` and `~/.config/zsh/conf.d/*`
(deployed by chezmoi, so `ucli chezmoi-apply` refreshes it). Nothing in that
layer is ucli-specific magic — the same files work in the dev box.

On **CachyOS**, skip steps 3–6 — Calamares already did DE + Snapper/Limine:

```bash
chezmoi init --apply https://github.com/dcizov/dots.git
ucli cli                     # shell tier (optional)
ucli apps                    # apps, flatpaks, Firefox config (also adds ghostty/firefox)
ucli devmode                 # optional
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
# 2. Create snapshot (before chezmoi apply)
sudo arch-snapper-limine.sh --yes

# 3. Later, deploy dotfiles and continue:
chezmoi init --apply https://github.com/dcizov/dots.git
# or without apply:
chezmoi init https://github.com/dcizov/dots.git
chezmoi apply -v

# 4. Continue with ucli:
ucli setup-system
ucli cli
ucli devmode
ucli apps
```

## Arch system setup

```bash
ucli setup-snapshots      snapshots + boot entries (skips CachyOS)
ucli system               system menu (checks and maintenance helpers)
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
