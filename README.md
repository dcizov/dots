# Workstation setup

Personal post-install setup for Arch and CachyOS. Managed with `chezmoi`, run with `ucli` (a `just` wrapper around `~/.config/ucli/justfile`).

This repo is not an OS installer. Archinstall/CachyOS installs the base system. This repo applies my dotfiles and gives me a small set of post-install commands.

All package decisions are backed by the [Arch Linux package database](https://archlinux.org/packages/) and the [Arch Wiki](https://wiki.archlinux.org/).

## Supported workflows

| Machine | Installer | DE choice | Snapper/Limine | This repo's role |
|---------|-----------|-----------|----------------|------------------|
| Arch minimal (laptop) | archinstall (minimal profile, console login) | Manual after first boot (`just setup-desktop`) | You run `ucli setup-snapshots` | Full setup: DE → packages → dotfiles → snapshots |
| CachyOS (desktop) | Calamares GUI (picks DE during install) | Already installed by Calamares | Calamares handles it | Dotfiles + packages only (`ucli devmode`, `ucli apps`) |

## Fresh install on Arch minimal (console → GUI)

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

# 5. optional: drop DE packages you never use (snapshot first, it is reversible)
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

What each layer actually puts on disk:

| Layer | Comes from | Contents |
|---|---|---|
| dotfiles | `chezmoi apply` | `~/.zshrc`, `~/.config/zsh/conf.d/*` (aliases, functions, fzf, prompt), `~/.config/starship.toml`, `~/.config/ghostty`, `~/.config/mozilla` |
| system | `ucli setup-system` | bootstrap (git, chezmoi, just, zsh), cpu/gpu, system tools, fonts, gum + pipx |
| desktop | `ucli setup-system` → `setup-desktop.sh` | DE package set with skip/replace matrix, **ghostty**, **firefox**, GNOME extension set, snapshot |
| shell | `ucli cli` | oh-my-zsh, 4 plugin clones into `$ZSH_CUSTOM/plugins`, `chsh -s zsh`, cosmetic tooling (starship, eza, bat, zoxide, atuin, tealdeer, glow, fzf) |
| apps | `ucli apps` | `APPS` (pacman) + `APP_FLATPAKS` (flatpak) + `MANUAL_AUR` (shelly) + Betterfox `user.js`, extension list, Firefox GNOME theme |
| dev | `ucli devmode` | `DEV_CLI` plumbing + `DEV` stack + dev box |

`ucli cli` on top of a plain zsh: oh-my-zsh + plugins is the standard setup, and
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

**Shelly** is an AUR package (Seafoam-Labs/Shelly-ALPM), installed via `paru`:
https://aur.archlinux.org/packages/shelly

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

## ucli

```bash
ucli                      list every recipe (hidden `_`-prefixed ones omitted)
ucli --choose             picker (gum → fzf → plain select)
ucli usage                the short version of this README
ucli profile              configured + detected profile facts
ucli doctor               health check (chezmoi, zsh, commands, dev box)
ucli validate             package array check
ucli inventory            package/app/settings inventory
```

## Install

```bash
ucli setup-system         first-machine profile (packages + basic setup)
ucli cli                  shell tier: oh-my-zsh + plugins + zsh login shell + cosmetics
ucli devmode              developer wizard — plumbing, apps, dev box (re-runnable)
ucli gaming               gaming profile
ucli apps                 personal apps and overrides
```

Four package tiers live in `private_dot_config/ucli/packages.bash`:

| Tier | What it is | Installed by |
|---|---|---|
| `UCLI_RUNTIME` | what ucli itself needs: `gum` (menus, wizard) and `python-pipx` (gext) | `base` → `ucli setup-system`, `ucli setup-desktop` |
| `DESKTOP_ESSENTIALS` | `ghostty` + `firefox` — the terminal and browser the dotfiles assume | `desktop` mode → `ucli setup-system`/`setup-desktop`; also `ucli apps` |
| `CLI` | the shell tier: `starship bat eza zoxide atuin tealdeer glow fzf` **plus** what `install-shell.sh` does — oh-my-zsh, the four plugin clones into `$ZSH_CUSTOM/plugins`, and `chsh -s zsh` | `ucli cli` |
| `DEV_CLI` | engineering plumbing: `jq yq ripgrep fd tree duf direnv mise lazygit neovim vim tmux shfmt` — needed the moment you touch a repo | `ucli devmode` |
| `DEV` | the heavy stack: `base-devel podman distrobox docker* podman-desktop vscodium-bin` | `ucli devmode` (`--force` bypasses the role check) |

`dev` mode selects `dev-cli` first, so the heavy stack always arrives with its
plumbing. `ucli cli` pulls its own prerequisites first (`SHELL_DEPS`: zsh, git,
curl), so it works on a machine that never ran `ucli setup-system`.
`ucli full-profile` (a.k.a. `install-packages.sh full`) is
`base + cli + dev + gaming`.

`base` does not install a desktop: `setup-desktop.sh` owns that step, so the
skip/replace matrix, ghostty/firefox, the extension set and the snapshot all
happen in one place. `install-packages.sh full` still includes `desktop`.

`base` installs the zsh *binary* (it is in `BOOTSTRAP`, and the dev box and the
dotfiles expect it) but takes no opinion on your login shell — oh-my-zsh,
plugins and `chsh` belong to `ucli cli`. Without it, `~/.zshrc` still works: it
sources oh-my-zsh only when present and prints a hint otherwise.

`ucli devmode` is a wizard, modelled on `ujust devmode`: one `gum choose
--no-limit` screen with sections and preselection, a summary + confirm, a
progress bar with per-step ✓/✗, and a marker at
`~/.local/state/ucli/devmode`. Re-running offers *"add more tools?"* and
preselects last time's picks. Non-TTY runs install everything:

```bash
ucli devmode              # wizard on a TTY, everything otherwise
ucli devmode --all        # every item, no menu (CI)
ucli devmode --status     # marker + version gates
ucli devmode --reset      # forget the marker, wizard from scratch
```

`private_dot_config/ucli/packages.bash` is the package source of truth;
`ucli validate` checks the arrays against it.

Extras that are deliberately not top-level: `ucli --choose` exposes the rest
(`shell`, `paru`, `shell-overrides`, `full-setup`, …).

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

## GNOME

```bash
ucli gnome                GNOME menu (extensions, settings backup, apply)
```

GNOME is curated in `packages.bash`. Package group contents from
[archlinux.org/groups/x86_64/gnome/](https://archlinux.org/groups/x86_64/gnome/).

## Dev box

The `dev` box is a rootless distrobox on **Debian 13 (trixie)**, defined
entirely in this repo:

| file | role |
|---|---|
| `private_dot_config/distrobox/dev.ini` | manifest: image, packages, init hook |
| `private_dot_config/distrobox/executable_provision-dev.sh` | provisioning (nvm + Node LTS, PHP 8.5 from Sury, composer, oh-my-zsh, sshd) |
| `private_dot_config/distrobox/devbox.env` | per-machine tunables (`NODE_CHANNEL`, `PHP_BRANCH`, `DEVBOX_SSH_PORT`) |
| `private_dot_config/ucli/scripts/devbox/executable_devbox-reconcile.sh` | create-or-update, the single entry point |

```bash
ucli devbox              # menu: reconcile, shell, versions, log, reprovision,
                         #       recreate, dry-run, vscode-doctor, vscode-bisect
ucli devbox-reconcile    # create the box, or bring it in line with this commit
ucli devbox-shell        # distrobox enter dev
```

The rarely-typed actions are hidden recipes (`_devbox-versions`, `_devbox-recreate`,
`_devbox-log`, …) so the list stays readable — they still run if you name them,
and the menu is the discoverable path:

```bash
ucli --show _devbox-recreate    # what the menu entry runs
ucli _devbox-versions           # direct
```

The menus use `gum` when it is installed (the TUI ujust uses), then `fzf`, then
a plain numbered list — `UCLI_MENU=gum|fzf|select` forces one. `gum` is part of
the `UCLI_RUNTIME` tier, so `ucli setup-system` and `sudo ucli setup-desktop`
bring it in; `fzf` comes with `ucli cli`.

`distrobox assemble create` on its own only creates a bare container — no Node,
no PHP, nothing provisioned. Always go through `ucli devbox-reconcile`
(or `ucli devmode`, which calls it).

After a full run: `debian 13.x`, `node v26.x`, `php 8.5.x`, `composer 2.x`,
sshd on `$DEVBOX_SSH_PORT` (default 2222).

Dev databases run on the host, not in the box:

```bash
cd ~/.config/dev-services
docker compose up -d
docker compose ps
docker compose down
```

Published on loopback only (`127.0.0.1:5432`, `:3306`, `:6379`), which is
reachable from inside the box because distrobox shares the host network
namespace. Keep app connection strings on `127.0.0.1`, not `localhost`
(`localhost` resolves to `::1` first and the port mapping is IPv4).

## Maintenance

Ported from Bluefin's `ujust`, adapted to pacman/AUR + distrobox:

```bash
ucli update            # pacman -Syu, AUR (paru/yay), flatpak, mise, then the box
ucli clean-system      # dangling images, unused flatpaks, old pkg cache (asks first)
ucli report            # machine + toolchain facts to ~/report-<date>.txt
ucli logs              # menu: this boot / last boot / devbox provision log / pacman
ucli changelogs        # what the last pacman transaction changed
ucli state             # versioned setup gates + devmode marker
ucli bios              # reboot into firmware settings (asks first)
ucli bios-info         # board + firmware version
```

`ucli update` warns about foreign (AUR / locally built) packages and asks
before upgrading — the Arch analogue of `ujust update` refusing to run while
the bootc image has layered packages. `UCLI_YES=1` (or a non-interactive run)
proceeds silently.

Two shared helpers were ported from Bluefin and are reused across scripts:

| File | What it gives you |
|---|---|
| `~/.config/ucli/scripts/lib/ui.sh` | `ui_title` / `ui_box` / `ui_summary`, `ui_choose_multi` (sections + preselect), `ui_step` (block progress bar with ✓/✗) |
| `~/.config/ucli/scripts/lib/version-script.sh` | `vs_check` / `vs_commit` / `vs_list` — a versioned hook gate: a step runs once per version token (counter or content hash) and is retried until it succeeds |

Current gates: `vscodium-extensions` (hash of `extensions.txt`), `devmode`.
Inspect them with `ucli state`; force a re-run with `ucli devmode --reset` or
`ucli vscodium-extensions --force`.

`clean-system` never touches named volumes: `dev_pgdata`, `dev_mysql` and
`dev_redis` survive it, and it only prunes *dangling* images and *anonymous*
volumes. Bluefin's `ujust clean-system` prunes unused named volumes; that would
delete your databases, so it is deliberately not copied.

`report` writes a local file — no pastebin upload, nothing from the environment.

## Chezmoi

Use chezmoi directly:

```bash
chezmoi diff
chezmoi apply -v
chezmoi update -v
chezmoi cd
```

VSCodium owns `~/.vscode-oss/argv.json` at runtime (it writes a
`crash-reporter-id` on first launch), so that one file shows up in
`chezmoi diff` after VSCodium runs. `dot_vscode-oss/argv.json` is the source of
truth for the API proposals open-remote-ssh needs; apply it deliberately when it
changes:

```bash
chezmoi apply --force ~/.vscode-oss/argv.json
```

## Checks

```bash
chezmoi cd
just --justfile private_dot_config/ucli/justfile --list
find . \( -name '*[*]*' -o -name '*(http*' \) -print    # autolinked filenames
bash -n private_dot_config/distrobox/executable_provision-dev.sh
bash -n private_dot_config/ucli/scripts/devbox/executable_devbox-reconcile.sh
chezmoi execute-template < run_once_before_00-bootstrap-arch.sh.tmpl | sed -n '1,8p'
chezmoi execute-template < run_onchange_after_90-ucli-install.sh.tmpl | sed -n '1,12p'
exit
chezmoi diff
chezmoi apply -v
ucli doctor
ucli validate
```

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