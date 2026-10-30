# Workstation setup

Personal post-install setup for Arch and CachyOS. Managed with `chezmoi`, run with `ucli`.

This repo is not an OS installer. Archinstall/CachyOS installs the base system. This repo applies my dotfiles and gives me a small set of post-install commands.

## First run

```bash
sudo pacman -Syu
sudo pacman -S --needed git chezmoi
chezmoi init --apply git@github.com:YOURUSER/dotfiles.git
ucli install
ucli doctor
```

## ucli

```bash
ucli                 list recipes
ucli --choose        picker
ucli profile         profile + detected facts
ucli doctor          health check
ucli validate        package list check
ucli inventory       package/app/settings inventory
```

## Install

```bash
ucli install
ucli install-desktop
ucli install-dev
ucli install-gaming
ucli install-profile
ucli install-flatpak-profile
```

`packages.bash` is the package source of truth.

## Arch system setup

```bash
ucli system-check
ucli arch-snapper-limine-dry
ucli arch-snapper-limine
ucli snapshot-fresh
```

The Arch Snapper/Limine script skips CachyOS.

## GNOME

```bash
ucli install-desktop
ucli install-gnome-user-extensions
ucli gnome-settings-backup
```

GNOME is curated in `packages.bash`.

## Dev box

```bash
DBX_CONTAINER_MANAGER=podman distrobox assemble create --file ~/.config/distrobox/dev.ini
distrobox enter dev
```

Dev databases:

```bash
cd ~/.config/dev-services
docker compose up -d
docker compose ps
docker compose down
```

## Chezmoi

Use chezmoi directly:

```bash
chezmoi diff
chezmoi apply -v
chezmoi update -v
chezmoi cd
```

## Checks

```bash
chezmoi cd
just --justfile private_dot_config/ucli/justfile --list
find . \( -name '*[*]*' -o -name '*(http*' \) -print
chezmoi execute-template < run_once_before_00-bootstrap-arch.sh.tmpl | sed -n '1,8p'
chezmoi execute-template < run_onchange_after_90-ucli-install.sh.tmpl | sed -n '1,12p'
exit
chezmoi diff
chezmoi apply -v
ucli doctor
ucli validate
```
