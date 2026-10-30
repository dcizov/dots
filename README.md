# Workstation setup

Personal post-install setup for Arch and CachyOS. Managed with `chezmoi`, run with `ucli` (a `just` wrapper around `~/.config/ucli/justfile`).

This repo is not an OS installer. Archinstall/CachyOS installs the base system. This repo applies my dotfiles and gives me a small set of post-install commands.

## First run

```bash
sudo pacman -Syu
sudo pacman -S --needed git chezmoi just
chezmoi init --apply git@github.com:dcizov/dots.git
# or, non-interactively:
#   curl -fsSL https://install.wtfaq.tech | bash -s -- --yes
ucli usage
ucli doctor
```

`chezmoi init --apply` writes the dotfiles and the ucli wrapper, then runs
`run_once_before_00-bootstrap-arch.sh.tmpl` (git/chezmoi/just if missing) and
`run_onchange_after_90-ucli-install.sh.tmpl`. No `run_*` script starts, stops or
enters a container — chezmoi ships files, `ucli` performs actions.

## ucli

```bash
ucli                      list every recipe (hidden `_`-prefixed ones omitted)
ucli --choose             fuzzy picker
ucli usage                the short version of this README
ucli profile              configured + detected profile facts
ucli doctor               health check (chezmoi, zsh, commands, dev box)
ucli validate             package array check
ucli inventory            package/app/settings inventory
```

## Install

```bash
ucli setup-system         first-machine profile (packages + basic setup)
ucli cli                  shell CLI experience
ucli devmode              developer tools — this also reconciles the dev box
ucli gaming               gaming profile
ucli apps                 personal apps and overrides
```

`private_dot_config/ucli/packages.bash` is the package source of truth;
`ucli validate` checks the arrays against it.

Extras that are deliberately not top-level: `ucli --choose` exposes the rest
(`shell`, `paru`, `shell-overrides`, `full-setup`, …).

## Arch system setup

```bash
ucli setup-snapshots      snapshots + boot entries (skips CachyOS)
ucli system               system menu (checks and maintenance helpers)
```

The Snapper/Limine script skips CachyOS.

## GNOME

```bash
ucli gnome                GNOME menu (extensions, settings backup, apply)
```

GNOME is curated in `packages.bash`.

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
ucli devbox-reconcile     # create the box, or bring it in line with this commit
ucli devbox-versions      # debian / node / npm / php / composer inside the box
ucli devbox-shell         # distrobox enter dev
ucli devbox-recreate      # rebuild — only needed for image/volumes/init_hooks changes
ucli devbox-reprovision   # re-run provisioning without recreating
ucli devbox-log           # /var/log/devbox-provision.log from the last run
```

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
