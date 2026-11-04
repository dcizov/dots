# Getting started

A console-only Arch install becomes a configured desktop in four commands. This
page is the walkthrough: what each step does, what it installs, and where you
change the defaults. The reference pages — [tiers](tiers.md),
[desktop](desktop.md), [operations](operations.md), [distros](distros.md),
[install](install.md) — go deeper; nothing here is only here.

Read it once before running anything. It takes five minutes; the setup takes
twenty.

## What this is

- **A post-install setup, not an installer.** `archinstall` (or Calamares on
  CachyOS) puts the base system down; this repo does everything after that.
- **One command per layer.** `ucli` is a thin `just` wrapper over
  `~/.config/ucli/justfile`, so there is no daemon, no state machine, no hidden
  service — every recipe is a script you can read.
- **Idempotent by construction.** Every step can be re-run, and every step can be
  skipped and done later.

## What you get

```
console Arch ──► snapshots ──► desktop + shell + dotfiles ──► apps ──► dev box
```

| After | You have |
|---|---|
| step 1 | `ucli` on `PATH`, and nothing else |
| step 2 | rollback-able snapshots with boot-menu entries |
| step 3 | GNOME (or KDE/Hyprland), a terminal, Firefox, zsh + oh-my-zsh + starship, all dotfiles |
| step 4 (optional) | cosmetics, personal apps, dev toolchain, dev box, games |

## Before you start

| Requirement | Why |
|---|---|
| Arch or CachyOS with `pacman` and systemd | every script is `pacman`-based ([distros](distros.md)) |
| `archinstall` minimal profile, console login | the desktop is step 3, not the installer's job |
| Working network | packages come from the repos, AUR and Flathub |
| **btrfs root**, if you want snapshots | step 2 refuses on anything else; everything else still works |
| ~15–25 min, a few GB | mostly `pacman` download time |

You do not need to know `chezmoi` or `just` beforehand. `ucli` is the only command
you type; `chezmoi diff` and `just --list` stay available when you want them.

## Step 1 — bootstrap (no root, ~1 minute)

```bash
curl -fsSL https://raw.githubusercontent.com/dcizov/dots/main/install.sh | bash -s -- --yes
```

Three equivalent alternatives if you would rather read it first or pin a branch —
they are listed in [install](install.md#running-the-bootstrap-no-project-domain).

**What happens**

1. `pacman -S ca-certificates curl git chezmoi just` (the only root prompt).
2. `chezmoi init` against the repo — dotfiles live in `~/.local/share/chezmoi`.
3. `chezmoi apply` of exactly four targets: `~/.local/bin/ucli`, `~/.config/ucli`
   (justfile, recipes, `packages.bash`, `scripts/lib`), `~/.local/share/ucli/scripts`,
   and `~/.bash_profile` (which puts `~/.local/bin` on `PATH`).

**What it deliberately does not do:** no zsh, no oh-my-zsh, no starship, no
terminal config, no Firefox config. A machine that will sit at a console does not
need them, and every file you skip here is a smaller snapshot. Those files are
held back by `.chezmoiignore`, which asks `lookPath` on every apply — they land on
the apply that runs *after* the programs exist, which is step 3.

**Check it**

```bash
exec bash -l          # re-read ~/.bash_profile → ~/.local/bin on PATH
ucli doctor           # shell-tier items print "—" (expected on a console-only box)
ucli usage            # the short version of everything below
```

## Step 2 — snapshots (root, 1–2 minutes)

```bash
ucli setup-snapshots
```

**What it does:** verifies the `@ @home @log @pkg` btrfs layout, writes
`/etc/snapper/configs/root`, installs `snapper snap-pac limine` plus
`limine-snapper-sync` and `limine-mkinitcpio-hook` (AUR), wires the `mkinitcpio`
hooks and `/etc/default/limine`, enables the cleanup timer, and takes snapshot #1.

**Why first:** steps 3 and 4 are the ones that touch hundreds of packages. With
the snapper config in place, every later step can take a restore point before it
starts, and Limine lists them in the boot menu.

**CachyOS:** the installer already owns all of this, so the script prints what it
found and exits. `--force` runs the Arch path anyway. Add `--no-snapshot` to
configure without taking snapshot #1.

**Check it**

```bash
snapper -c root list
ucli snapshot --dry-run        # the exact snapper call, changes nothing
```

> No btrfs? Skip this step. Every later snapshot prints a note, exits 0, and the
> setup continues — "nothing to snapshot" is never treated as a failure.

## Step 3 — the machine (root, 15–25 minutes)

```bash
ucli setup-system gnome        # or: kde, hyprland
```

This is the one big compound step. `install-profile.sh` runs these in order:

| # | What | Installs / writes |
|---|---|---|
| 1 | preflight | warns (and asks, on a TTY) when there is no snapper config |
| 2 | restore point | `before setup-system` — the same snapshot script as every other step |
| 3 | `base` | `BOOTSTRAP` (git, chezmoi, just, zsh, openssh, curl, nano, less, rsync, wget), CPU microcode, GPU drivers, system tools (+ `fwupd`), multimedia codecs, hardware-detected extras (`fprintd`, `libinput-tools`), fonts, `UCLI_RUNTIME` (gum + python-pipx) — no flatpaks yet |
| 4 | the desktop | the DE package set through the skip/replace matrix in `packages.bash` (`gnome` group, `plasma`, or the Hyprland set) |
| 5 | terminal + browser | Firefox everywhere, plus **ghostty** on GNOME/Hyprland or **kwi** on KDE |
| 6 | shell tier | zsh, oh-my-zsh, the plugin clones from `plugins.txt`, starship, `chsh -s zsh` |
| 7 | dotfiles | `chezmoi apply` as you — now that the programs exist, `~/.zshrc`, `~/.config/zsh`, `starship.toml`, `~/.config/ghostty`, `~/.config/ucli/firefox` deploy |
| 8 | GNOME extensions | `gext` via pipx, then the `system` set (dash-to-dock, blur-my-shell, gsconnect, search-light, copyous) and the `personal` set if you defined one (GNOME only) |
| 9 | Firefox profile | creates the profile headlessly, copies the Betterfox `user.js` into it, and on GNOME installs firefox-gnome-theme |
| 10 | snapshot | `<DE> Setup` |

On CachyOS, microcode, GPU and bootloader support are skipped — `chwd` and the
installer own them.

**Then log out and back in.** zsh becomes your login shell, and the extensions
load with the session.

| Flag | Effect |
|---|---|
| `ucli setup-system kde` / `hyprland` | pick the desktop explicitly (omit it to auto-detect, then prompt) |
| `--no-snapshot` | no restore points this run — forwarded to every snapshot, including the desktop one |
| `--yes` | do not ask about the missing-snapper warning |
| `--force` | re-run the gated Firefox steps (Betterfox copy, GNOME theme) |

**Check it**

```bash
ucli doctor                    # every section should be OK / WARN-free except optional bits
chezmoi diff                   # empty means the dotfiles are deployed
echo $SHELL                    # /usr/bin/zsh after re-login
ucli state                     # which versioned steps have run
```

## Step 4 — the extras (all optional, any order)

Each is independent; run what you want, when you want.

| Command | Installs | Notes |
|---|---|---|
| `ucli cli` | `CLI`: atuin, bat, eza, fzf, glow, tealdeer, zoxide | re-runs the shell tier first, so it works even if you skipped step 3 |
| `ucli apps` | `APPS` + `APP_FLATPAKS` (desktop tooling + flatpak housekeeping) + `MANUAL_AUR` (shelly) + your `PERSONAL_*` overlay, then the Firefox extension lists and the personal GNOME extension set | Firefox + terminal are included, so this also works as a one-shot "give me a browser" — and the profile config (Betterfox, theme) comes with it via the shared script |
| `ucli devmode` | wizard: dev CLI (jq, ripgrep, fd, tmux, mise, …), dev stack (docker, podman for distrobox, distrobox, vscodium) **with `docker.service` enabled and your user added to the `docker` group**, performance tooling (perf, bcc, bpftrace, sysprof, …), dev flatpaks, VSCodium extensions, Firefox dev extensions, the Debian dev box | `--all` everything, `--status`, `--reset`; re-running offers "add more?" |
| `ucli gaming` | `GAMING`: steam, mangohud, gamemode + 32-bit bits | role-gated; `--force` overrides |

## Configuring it

Four levers, ordered by how often you will touch them.

### 1. Per-machine shell switches — `~/.config/zsh/local.zsh`

Nothing machine-specific belongs in the repo. Copy the example once:

```bash
cp ~/.config/zsh/local.zsh.example ~/.config/zsh/local.zsh
```

Then flip what you dislike. Every block checks `UCLI_SHELL_ENABLE_*`; set `0` to
turn it off, delete the line to get the default (on).

| Flag | Turns off |
|---|---|
| `UCLI_SHELL_ENABLE_EZA` | `ls`/`ll` → eza |
| `UCLI_SHELL_ENABLE_BAT` | `cat` → bat |
| `UCLI_SHELL_ENABLE_FD` | `fd` integration |
| `UCLI_SHELL_ENABLE_RG` | ripgrep integration |
| `UCLI_SHELL_ENABLE_DUF` | `df` → duf |
| `UCLI_SHELL_ENABLE_TLDR` | tealdeer integration |
| `UCLI_SHELL_ENABLE_GLOW` | `md` → glow |
| `UCLI_SHELL_ENABLE_ATUIN` | atuin history |
| `UCLI_SHELL_ENABLE_DIRENV` | direnv hook |
| `UCLI_SHELL_ENABLE_ZOXIDE` | zoxide (`z`) |
| `UCLI_SHELL_ENABLE_MISE` | mise activation |

`local.zsh` is sourced before `conf.d/*`, is never chezmoi-managed, and
`ucli doctor` tells you if it is missing.

### 2. What gets installed — `packages.bash` + `packages.local.bash`

One file, plain bash arrays. Add a package by adding a line; remove one by
deleting it. The interesting arrays:

| Array | Used by | Contains |
|---|---|---|
| `BOOTSTRAP` / `SHELL_TOOLS` | step 3, `ucli cli` | git, zsh, starship, curl, … |
| `DESKTOP_<DE>_BASE` | step 3 | the DE itself |
| `DESKTOP_TERMINAL_<DE>` | step 3 | ghostty (GNOME/Hyprland), kwi (KDE) |
| `DESKTOP_BROWSER` | step 3, `ucli apps` | firefox |
| `CLI` / `DEV_CLI` / `DEV` / `GAMING` | steps 4 | the opt-in tiers |
| `APPS` / `APP_FLATPAKS` / `MANUAL_AUR` | `ucli apps` | personal apps |
| `DESKTOP_SKIP_<DE>` / `DESKTOP_REPLACE_<DE>` | step 3 | the skip/replace matrix |

Anything personal — a password manager, Spotify, `neovim`, a wallpaper tool, your
own GNOME extensions — belongs in the **overlay** instead, so the repo keeps
installing the same opinionated set on every machine:

```bash
cp ~/.config/ucli/packages.local.bash.example ~/.config/ucli/packages.local.bash
```

| Overlay array | Installed by |
|---|---|
| `PERSONAL_PKGS` | `ucli apps` |
| `PERSONAL_DEV` | `ucli devmode` |
| `PERSONAL_FLATPAKS` | `ucli apps` |
| `PERSONAL_GNOME_EXTENSIONS` (`"PK:UUID"`) | `ucli setup-extensions` |

Firefox works the same way but with files: `~/.config/ucli/firefox/extensions.txt`
ships empty, and `personal-extensions.txt` (copy the `.example`) is yours.

Then re-run the step that owns the array (or nothing at all — `ucli setup-system`
and `ucli apps` are both cheap no-ops for what is already installed). Check it
with:

```bash
ucli check          # offline: syntax, recipes, arrays, shellcheck
ucli validate       # every name in every array exists in pacman or the AUR
```

Full inventory and the terminal-per-desktop reasoning: [tiers](tiers.md).

### 3. Machine profile — chezmoi data

`chezmoi init` asks five questions once and stores the answers in
`~/.config/chezmoi/chezmoi.toml`:

| Key | Values | Affects |
|---|---|---|
| `machine` | auto / laptop / workstation | informational (`ucli profile`) |
| `desktop` | auto / gnome / kde / hyprland | which DE arrays a manual `ucli setup-system` defaults to |
| `terminal` | auto / ghostty / kitty / kwi | an explicit answer deploys that terminal's config even before it is installed |
| `role` | dev / dev-gaming / minimal | whether `dev` packages install without `--force` |
| `gaming` | true / false | same for `ucli gaming` |

Change them with `chezmoi init` again, or edit the `[data]` block by hand, then
`ucli chezmoi-apply`. `ucli profile` prints what was configured *and* what was
detected.

### 4. Versioned steps and `--force`

Three things are skipped when their input has not changed, so a re-run is instant:

| Gate | Keyed on | Force with |
|---|---|---|
| `gnome-extensions-system`, `-personal` | hash of `packages.bash` (+ overlay for `personal`) | `ucli setup-extensions --force` |
| `firefox-betterfox` | hash of `~/.config/ucli/firefox/user.js` | `ucli setup-desktop --force` (or `ucli apps --force`) |
| `vscodium-extensions` | hash of `extensions.txt` | `ucli vscodium-extensions --force` |

`ucli state` lists them with their hashes. Gates only commit on success, so a
failed run retries next time.

### Where things land

| Path | What |
|---|---|
| `~/.config/zsh/` | `plugins.txt` (the one plugin list), `conf.d/*`, `local.zsh` |
| `~/.config/ucli/` | justfile, recipes, `packages.bash`, `scripts/lib`, `firefox/` sources |
| `~/.local/bin/ucli` | the wrapper everything routes through |
| `~/.local/share/ucli/scripts/` | the install/system/check scripts themselves |
| `~/.local/share/ucli/aur-helper` | which AUR helper this machine uses |
| `~/.local/state/ucli/` | gates, motd mode, devmode marker |
| `/etc/ucli/installation-snapshot` | the snapshot id of snapshot #1 |
| `~/.oh-my-zsh/` | oh-my-zsh + the plugin clones (not chezmoi-managed) |

Firefox is the one app whose files are split: profiles stay Firefox's own
(`~/.config/mozilla/firefox` on 147+, `~/.mozilla/firefox` on older installs) and
ucli only copies `~/.config/ucli/firefox/user.js` into them.

## Day to day

| Command | Does |
|---|---|
| `ucli update` | pacman + AUR + flatpaks + mise + dev box, after showing foreign packages |
| `ucli snapshot "before X"` | restore point, same script every step uses |
| `ucli clean-system` | dangling containers, unused flatpaks, old package cache |
| `ucli doctor` | what is missing right now, section by section |
| `ucli check` | the offline static checks (also CI) |
| `ucli logs` / `report` / `inventory` | log menu / a file you can paste / a package+app+settings dump |
| `ucli motd on\|always\|off` | the login banner (fastfetch), login shells only by default |
| `ucli config-audit` | `.pacnew` files waiting to be merged + packaged files you edited |
| `ucli sync` | Syncthing between two machines (installs, enables the service, prints the device ID) |
| `ucli devbox-create ubuntu` | throwaway container from a stock distro image |
| `ucli chezmoi-apply` | re-deploy the dotfiles after editing the repo |

[operations](operations.md) has the long version, including the chezmoi workflow.

## Changing your mind

- **Different desktop:** `ucli setup-desktop kde`. It installs the new DE next to
  the old one; drop what you no longer use with `ucli debloat-desktop`.
- **Different terminal:** edit `DESKTOP_TERMINAL_<DE>`, or install the terminal
  yourself and run `ucli chezmoi-apply` — the config follows the program.
- **Undo everything:** `ucli uninstall` (takes a snapshot first, asks before
  removing packages). `--no-snapshot` skips the restore point.

## If something looks wrong

| Symptom | Cause |
|---|---|
| `— zsh … expected on a console-only box` | no desktop yet; run step 3 |
| `note: snapper is not installed`, steps continue | no btrfs or no step 2; snapshots are optional |
| GNOME extensions "unchanged since the last run" | the gate; `ucli setup-extensions --force` |
| A config directory is missing | `.chezmoiignore` gates it on `lookPath`; install the program, then `ucli chezmoi-apply` |
| `missing: kwi` on KDE | AUR-only as `kwi-git`; Konsole from `plasma` is the fallback |
| CachyOS "installer-owned, nothing to do" | correct; see [distros](distros.md) |

Run `ucli doctor` before asking anywhere else — it names the layer that is wrong
and the command that fixes it.
