# Distros: Arch, CachyOS, and other Arch derivatives

Everything in this repo assumes Arch's layout — `pacman`, `/etc/pacman.conf`,
`/etc/snapper`, `mkinitcpio`, `limine`, `/etc/os-release`, systemd units. CachyOS
is Arch with extra repositories on top, so those paths are identical; what
differs is *who owns* the pieces and which repo a package comes from.

`install.sh` accepts `arch`, `archlinux` and `cachyos` by name, and anything whose
`ID_LIKE` contains `arch` with a warning. `detect_distro_family` in
`scripts/lib/detect.sh` is the single place that decides.

## Paths

| Thing | Arch | CachyOS | Other Arch derivatives |
|---|---|---|---|
| OS identity | `/etc/os-release` → `ID=arch` | `ID=cachyos`, `ID_LIKE=arch` | `ID=endeavouros`/`garuda`/… , `ID_LIKE=arch` |
| Packages | `pacman` | `pacman` (same) | `pacman` (same) |
| Snapshots | `/etc/snapper/configs/root`, `/etc/conf.d/snapper` | same paths, **installer-owned** | same paths |
| Boot | `/etc/default/limine`, `/etc/mkinitcpio.conf` | same paths, **installer-owned** | same paths |
| Firefox profiles | `~/.config/mozilla/firefox` or `~/.mozilla/firefox` | identical | identical |
| KDE terminal (`kwi`) | AUR `kwi-git` | same, and CachyOS's extra repos may carry it sooner | AUR |
| `~/.local/bin`, `~/.config` | XDG as usual | identical | identical |

There is no per-distro path table to maintain beyond this: the differences are
ownership and repositories, not locations.

## Repositories

| | Arch | CachyOS |
|---|---|---|
| Official repos | `core`, `extra`, `multilib` | Arch's `core`/`extra`/`multilib` **plus** `cachyos`, and x86-64-v3/v4 recompiles (`cachyos-core-v3`, `cachyos-extra-v3`, `cachyos-v3`, …) listed *before* Arch's |
| Package names | the reference | the same names for Arch packages (recompiled), Cachy-flavoured ones marked (`linux-cachyos`, `cachyos-settings`, `chwd`) |
| AUR helper | not shipped: `install-aur-helper.sh` builds `paru` (AUR) | ships **shelly** since April 2026; `paru` and `shelly` are both *in the CachyOS repos* |
| `pacman -Si` | Arch repos only | searches all configured repos, so CachyOS packages resolve like official ones |

What the scripts do about it:

- `install-paru.sh` / `install-shelly.sh` check `pacman -Si` first and install
  from the repository when it is there (CachyOS), and only build from the AUR
  when it is not (Arch). A repo package is signed, updated with the system, and
  needs no `makepkg`.
- `install-aur-helper.sh` prefers shelly, then paru, then installs one. On CachyOS
  that is normally a no-op: shelly is already there.
- `install-packages.sh` resolves every name through `pacman -Si` and only falls
  back to the AUR (RPC check) for what the repos do not have. `MANUAL_AUR` (shelly)
  therefore installs from the CachyOS repo there and from the AUR on Arch.
- AUR *calls* still differ by helper: `paru -S …` vs `shelly install aur …`.
  That is why every script asks `install-aur-helper.sh --print-only` instead of
  hardcoding a helper.

## What is installer-owned on CachyOS

`ucli setup-system` skips these on CachyOS instead of fighting Calamares/chwd:

| Step | Arch (this repo does it) | CachyOS |
|---|---|---|
| CPU microcode | `CPU_INTEL` / `CPU_AMD` | skipped (`cachyos-settings`/installer) |
| GPU drivers | `GPU_AMD` / `GPU_INTEL` / `GPU_NVIDIA` | skipped; `chwd` handles hardware detection |
| Bootloader support | `BOOT_SUPPORT` | skipped |
| Snapper + Limine | `arch-snapper-limine.sh` writes the config, hooks and `/etc/default/limine` | script explains it is already wired and exits; `--force` overrides |

`ucli setup-snapshots --no-snapshot` on CachyOS prints what is already wired and
exits (add `--force` to run the Arch path anyway). For a restore point there, use
`ucli snapshot "…"` — the same script every other step uses.

## Firefox paths (the one path that moved)

Firefox 147 (January 2026) finally implemented XDG, so the profile root is now:

| Install | Profile root | Cache |
|---|---|---|
| Firefox 147+, new profile | `~/.config/mozilla/firefox/<profile>/` | `~/.cache/mozilla/firefox/` |
| Upgraded install, or `MOZ_LEGACY_HOME=1` | `~/.mozilla/firefox/<profile>/` | `~/.cache/mozilla/firefox/` |
| Flatpak | `~/.var/app/org.mozilla.firefox/config/mozilla/firefox/` | inside the sandbox |

Firefox keeps using an existing legacy root even on 147+, so both are live on
Arch and CachyOS depending on whether the machine was installed before or after
the change. `scripts/lib/firefox.sh` resolves it: `MOZ_LEGACY_HOME` first, then
whichever root has a `profiles.ini`, then the 147+ default. `ucli doctor` prints
which one it found.

The files this repo manages are **not** a Firefox path:

```
~/.config/ucli/firefox/user.js              # Betterfox + overrides
~/.config/ucli/firefox/extensions.txt       # extensions ucli apps installs
~/.config/ucli/firefox/dev-extensions.txt   # the devmode subset
```

They are copied into every profile that `profiles.ini` lists, which is the only
place Firefox reads `user.js` from. Keeping them under `~/.config/ucli/` also
means `ucli uninstall` cannot delete a profile directory by accident.

## Not supported

- **Artix** advertises `ID_LIKE=arch` but has no systemd; the `systemctl` steps
  (`gdm`, `sddm`, `snapper-cleanup.timer`) fail. Treat it as unsupported.
- **Manjaro** is Arch-based but ships its own lagging repos with renamed/held
  packages; it is not tested here and `pacman -Si` names may not match.
- Non-Arch distros are refused by `install.sh` with the detected `ID`/`ID_LIKE`
  rather than half-applying an Arch-only pipeline.
