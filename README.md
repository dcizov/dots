# Workstation setup

Personal post-install setup for Arch and CachyOS. Managed with `chezmoi`, run with `ucli` (a `just` wrapper around `~/.config/ucli/justfile`).

This repo is not an OS installer. Archinstall/CachyOS installs the base system. This repo applies my dotfiles and gives me a small set of post-install commands.

All package decisions are backed by the [Arch Linux package database](https://archlinux.org/packages/) and the [Arch Wiki](https://wiki.archlinux.org/).

## Supported workflows

| Machine | Installer | DE choice | Snapper/Limine | This repo's role |
|---------|-----------|-----------|----------------|------------------|
| Arch minimal (laptop) | archinstall (minimal profile, console login) | Manual after first boot (`just setup-desktop`) | You run `ucli setup-snapshots` | Full setup: ucli → snapshots → DE + packages + dotfiles → snapshot |
| CachyOS (desktop) | Calamares GUI (picks DE during install) | Already installed by Calamares | Calamares handles it | Dotfiles + packages only (`chezmoi init --apply`, then `ucli devmode`/`ucli apps`) |


## Quick start (Arch minimal → working machine)

```bash
curl -fsSL https://install.wtfaq.tech | bash     # git, chezmoi, just → ucli on PATH
ucli setup-snapshots                             # snapper + limine, snapshot #1
ucli setup-system gnome                          # base + DE + terminal + browser
                                                 # + shell tier + dotfiles + snapshot
ucli cli                                         # shell cosmetics
ucli apps                                        # apps, flatpaks, Firefox config
ucli devmode                                     # optional: dev tools + dev box
```

Two epochs. The bootstrap stops at "ucli works": `~/.local/bin/ucli`,
`~/.config/ucli`, `~/.local/share/ucli` and a `~/.bash_profile` that puts
`~/.local/bin` on `PATH`. No zsh, no starship, no terminal or browser config —
those arrive with `ucli setup-system`, which installs the programs and then runs
`chezmoi apply`. `.chezmoiignore` asks `lookPath` on every apply, so a config is
only ever deployed for a program that exists; that is what keeps the
fresh-install snapshot small enough to be worth keeping.

The terminal follows the desktop: **ghostty** on GNOME and Hyprland (GTK4, native
Wayland, already in the Adwaita stack / a first-class wlroots client), **kitty**
on KDE Plasma (a Qt desktop, no GTK theme dragged in). Firefox is installed
everywhere, and its profile stays Firefox's own — `~/.config/mozilla/firefox` on
147+, `~/.mozilla/firefox` on an upgraded install. ucli only copies
`~/.config/ucli/firefox/user.js` and the extension lists into each profile it
finds in `profiles.ini`; [docs/distros.md](docs/distros.md) has the path table
for both spellings, and for CachyOS's repositories.

Every step is idempotent and rerunnable on its own. `ucli doctor` says what a
machine is missing, `ucli check` runs the offline static checks, and
`ucli state` shows which versioned steps have already been applied.
[docs/install.md](docs/install.md) explains the order, what each step owns, and
why the snapshot comes before the rest.

## Documentation

| Doc | What is in it |
|---|---|
| [docs/install.md](docs/install.md) | The full pipeline step by step, the snapshot-only path (before chezmoi), Arch-specific notes, fresh-install readiness |
| [docs/tiers.md](docs/tiers.md) | Every package tier (`UCLI_RUNTIME`, `SHELL_TOOLS`, `DESKTOP_BROWSER`, `DESKTOP_TERMINAL_<DE>`, `CLI`, `DEV_CLI`, `DEV`, `GAMING`), what `ucli cli`/`devmode`/`apps` put on disk, per-machine shell flags in `local.zsh`, versioned gates and `--force` |
| [docs/desktop.md](docs/desktop.md) | Software replacement matrix (skip/replace per DE), the `ucli gnome` menu, GNOME settings backup/restore, adding backed-up settings to the repo |
| [docs/devbox.md](docs/devbox.md) | The distrobox dev box: creation, provisioning, versions, reconcile |
| [docs/operations.md](docs/operations.md) | `ucli update`/`clean-system`/`logs`/`state`/`report`, the chezmoi workflow, and what `ucli check` + `ucli doctor` verify |
| [docs/distros.md](docs/distros.md) | Arch vs CachyOS vs other Arch derivatives: paths, repositories, AUR helpers, what is installer-owned on CachyOS, and the Firefox profile paths |
| [docs/bluefin.md](docs/bluefin.md) | What `ujust bluefin-cli` actually does, what this repo took from it, and what it deliberately left |

## Repository layout

| Path | Deploys to | Contents |
|---|---|---|
| `dot_zshrc`, `private_dot_config/zsh/` | `~/.zshrc`, `~/.config/zsh/` | shell entrypoint, `plugins.txt` (the one plugin list), `conf.d/*`, `local.zsh.example` — deployed once zsh exists |
| `dot_bash_profile` | `~/.bash_profile` | `~/.local/bin` on `PATH` for the console epoch (ssh, TTYs, `su -`) |
| `private_dot_config/ucli/` | `~/.config/ucli/` | `justfile`, `recipes/*.just`, `packages.bash` (every package array), `scripts/lib/` |
| `private_dot_local/share/ucli/scripts/` | `~/.local/share/ucli/scripts/` | install, check (`check.sh`, `doctor.sh`), system, gnome, devbox, inventory scripts |
| `private_dot_local/bin/executable_ucli` | `~/.local/bin/ucli` | the `just` wrapper (`ucli <recipe>`, `ucli --choose`) |
| `private_dot_config/` `ghostty`, `kitty`, `VSCodium`, `ucli/firefox` | the matching `~/.config` paths | terminal (only the installed one), editor, and ucli's Firefox sources (`user.js`, extension lists) |
| `private_dot_config/distrobox/` | `~/.config/distrobox/` | dev box definition + `provision-dev.sh` |
| `run_*.sh.tmpl`, `install.sh` | — (run by chezmoi / the bootstrap) | bootstrap, plugin repair hook, theme scripts |

`.github/workflows/check.yml` runs `ucli check`'s script against the checkout on
every push and PR. `README.md`, `docs/` and `install.sh` are in
`.chezmoiignore` — they are repo furniture, not dotfiles.
