# Day to day

## Maintenance

Ported from Bluefin's `ujust`, adapted to pacman/AUR + distrobox:

```bash
ucli update            # pacman -Syu, AUR (paru or shelly), flatpak, mise, the box
ucli update --level minimal   # one ✓/✗ line per step, log tail on failure
ucli update --level prompt    # ask before every step
ucli update-timer      # status of the daily unattended upgrade (see below)
ucli clean-system      # dangling images, unused flatpaks, old pkg cache (asks first)
ucli fix               # repair: keyrings, db lock, orphans, cache, reinstall (see below)
ucli tweak             # turn a registered service on or off (see below)
ucli dns               # DNS presets for NetworkManager connections (see below)
ucli welcome           # what this machine is, what is pending, next steps
ucli report            # machine + toolchain facts to ~/report-<date>.txt
ucli logs              # menu: this boot / last boot / devbox provision log / pacman
ucli changelogs        # what the last pacman transaction changed
ucli state             # versioned setup gates + devmode marker
ucli bios              # reboot into firmware settings (asks first)
ucli bios-info         # board + firmware version (also in ucli system)
ucli config-audit      # unmerged .pacnew files + locally modified package files
ucli sync              # Syncthing: folder sync between two machines
ucli virt              # qemu/libvirt/virt-manager + libvirtd + the libvirt group
ucli ms-fonts          # Microsoft core fonts (AUR ttf-ms-fonts)
ucli mirrors           # rank pacman mirrors, keep the old list as *.bak
ucli fingerprint       # reader working in the DE's Settings (see below)
```

`ucli config-audit` is the Arch answer to Bluefin's `ujust check-local-overrides`
(which diffs `/usr/etc` against `/etc`): it lists what `pacdiff -o` says is
waiting to be merged plus every packaged file whose checksum changed, and exits 0
either way — drift is normal, but it should not be invisible. Read-only.

`ucli sync` installs Syncthing, enables `syncthing@<user>.service` (runs as you,
not root) and prints the Web GUI and this machine's device ID; pairing is the
same two-click dance as Bluefin's *Sync Folder*, because writing `config.xml`
behind the GUI's back would only fight it.

### Front door

`ucli welcome` is the CachyOS-Hello idea without a window: four lines that answer
*what is this machine, what is pending, how old is the restore point, do I need to
reboot*, then the recipes that are actually due.

```
  machine   GNOME · repo 77cbf57 (2 file(s) out of sync)
  pending   4 package update(s)
  snapshot  #12, 3h ago
  reboot    no
```

`ucli welcome --status` prints just that block — it is also what `ucli` shows
above its menu, so the first thing you see is state, not a list of verbs. A login
shell runs `ucli welcome --first-login` once per machine (it commits a version
gate, so it never repeats). Read-only, no sudo, no network: `pacman -Qu` reads the
local sync database.

### Repair (`ucli fix`)

The five repair actions CachyOS Hello puts behind buttons, as one namespace:

```bash
sudo ucli fix keyrings      # refresh pacman's keys; --reset re-initialises + repopulates
sudo ucli fix lock          # remove a stale /var/lib/pacman/db.lck (refuses while pacman runs)
sudo ucli fix orphans       # pacman -Qtdq, asked, then -Rns
sudo ucli fix cache         # paccache -rk2 + -ruk0, journal vacuum to 200M (--keep N)
sudo ucli fix native        # reinstall every repo package in place (--list first!)
```

Every one accepts `--dry-run`, and `ucli fix` with no argument prints the table.
Two deliberate choices: `fix lock` checks for an open handle (`fuser`) or a
running pacman/paru/shelly and refuses instead of corrupting the database; `fix
native` filters `pacman -Qnq` against the sync databases first (a package dropped
from the repos would otherwise fail the whole transaction) and wants `reinstall`
typed before it starts, because it re-downloads a few thousand packages.

### Tweaks (`ucli tweak`)

```bash
ucli tweak                  # registered switches, their units and state
sudo ucli tweak enable cups # installs the package (repos only) and start/ enables it
sudo ucli tweak disable cups
```

The registry is `TWEAKS` in `packages.bash` (see
[tiers](tiers.md#switches-tweaks-and-dns_presets)). State is systemd's, not a
file. Disabling keeps the package: uninstalling is `ucli debloat-desktop`'s job,
where a snapshot comes first.

### DNS (`ucli dns`)

```bash
ucli dns list                          # connections, their servers, the presets
ucli dns status                        # the active connection, one screen
sudo ucli dns set cloudflare           # preset from DNS_PRESETS
sudo ucli dns set "1.1.1.1 9.9.9.9"    # literal servers
sudo ucli dns set cloudflare --dot     # + DNS-over-TLS, when NM's plugin supports it
sudo ucli dns reset                    # back to DHCP-provided servers
```

Everything goes through `nmcli connection modify`, so it survives reboots with the
profile. `set` also sets `ipv4.ignore-auto-dns` / `ipv6.ignore-auto-dns`,
otherwise NetworkManager keeps prepending the DHCP servers and the preset is only
half-applied. `--connection <name>` targets another profile. DNS-over-TLS needs a
NetworkManager DNS plugin that can do it (`dns-systemd-resolved`); the property is
feature-detected, and when NM cannot do it the script says so rather than writing
a setting that does nothing.

### Upgrades (`ucli update`)

One script, three callers (the recipe, `--level`, and the timer). The order is
fixed, because the failure domains are:

1. a named Snapper restore point (`--no-snapshot` / `UCLI_NO_SNAPSHOT=1` skips it);
2. a warning listing foreign (`pacman -Qm`) packages — the Arch equivalent of
   Bluefin refusing to update a *layered* image;
3. `pacman -Syu` for the repos;
4. the AUR, **interactive runs only**;
5. Flatpaks, system-wide and per-user;
6. `mise upgrade`, as your user;
7. the dev box reconcile, interactive runs only;
8. a reboot hint when `/usr/lib/modules/$(uname -r)` is gone (the cheap, reliable
   "kernel changed" signal).

There is deliberately **no `set -e`**: a failed step is recorded, its last 15 log
lines are printed, and the remaining steps still run — a broken Flatpak remote must
not leave pacman half-applied. Exit status 1 means "something failed", with the
output saying which.

The AUR helper is resolved the same way the installer resolves it: `AUR_HELPER`
from `packages.bash` (or `packages.local.bash`) when it is set **and** installed,
otherwise shelly if installed, otherwise paru. `paru -Sua` and `shelly upgrade aur`
are the two upgrade paths; **yay is not wired anywhere** — this repo installs only
paru or shelly, so a yay branch would be dead code that looks supported. No helper
at all is reported as a skipped step rather than passing silently.

`--noconfirm` / `--no-confirm` is passed **only when nobody is at the keyboard**
(`UCLI_YES=1`, or no TTY — which includes the timer), for `pacman` and for the
helper alike. Interactively you keep pacman's replace/conflict questions (it still
writes `.pacnew` rather than overwriting config) and the helper's confirmation
prompt, i.e. the PKGBUILD diff before it builds.

### Scheduled upgrades (`ucli update-timer`)

```bash
ucli update-timer status               # state, next run, last result
sudo ucli update-timer on              # daily, up to an hour of jitter
sudo ucli update-timer on --time 04:30
sudo ucli update-timer off
```

The timer runs `update.sh --scheduled`: a restore point, repo packages, Flatpaks
(system-wide **and** yours), and mise — the last two as *you*, through
`runuser -u $UCLI_TIMER_USER`, because their files live in `$HOME` and a root-run
`flatpak update`/`mise upgrade` would reach the wrong installation entirely.

**It does not run the AUR or the dev box.** paru and shelly build as the invoking
user and stop at a confirmation prompt that *is* the PKGBUILD review; automating
that means answering "yes" to code you never saw. A half-built package mid-upgrade
is also exactly what `ucli update`'s foreign-package warning is about. The unit
files live in `/etc/systemd/system` and are written by the script; "is it on" is
`systemctl is-enabled ucli-update.timer`, not a file in `$HOME`.

### Mirrors

`ucli mirrors` is a port of CachyOS' `cachyos-rate-mirrors` with this repo's
rules on top:

```bash
ucli mirrors                  # rank, show the top mirrors, ask, then write
ucli mirrors --dry-run        # rank and show only — nothing is touched
ucli mirrors --country DE     # skip the geoip lookup
ucli mirrors --no-geo         # no lookup at all, engine default entry country
ucli mirrors --repos arch     # only /etc/pacman.d/mirrorlist
ucli mirrors --tool reflector # use reflector instead of rate-mirrors
```

| | |
|---|---|
| engine | `rate-mirrors` from **[extra]** (no AUR helper needed; `reflector` works too) |
| repos | `arch` always, plus `cachyos` when `/etc/pacman.d/cachyos-mirrorlist` exists |
| writes | `/etc/pacman.d/mirrorlist`, previous file kept as `mirrorlist.bak` |
| safety | Snapper snapshot first when snapper is configured (`--no-snapshot` off), confirmation before writing (`--yes` to skip) |

It runs as **your user**, not as root: rate-mirrors refuses root on purpose, and
only the final `install` needs `sudo`. Two things from the CachyOS original are
deliberately not copied — the four hardcoded RU mirrors it force-inserts at the
top of the list (this repo does not pin third-party mirrors on your machine), and
the `--allow-root` dance. The geoip entry country (`geoip.kde.org`, same source
as the original) and the China special case (test only Chinese mirrors, no
neighbours) are kept, both fail-soft.

Ranking takes ~30 s per repository and is measured, not guessed: the engine
downloads from candidate mirrors in parallel, so run it when the network is in
the state you want to optimise for.

### Fingerprint reader

`fprintd` comes with `base` when a reader is present (the `HARDWARE_FINGERPRINT`
array, decided by `lib/detect.sh`); what it does not do is make the finger
useful. `ucli fingerprint` covers the rest:

```bash
ucli fingerprint            # fprintd + daemon, then prints the enrollment step
ucli fingerprint --status   # reader, service, enrolled fingers, PAM state
ucli fingerprint --enroll   # enroll from the terminal (desktops without a page)
ucli fingerprint --pam      # also unlock/login/sudo with the finger
```

Enrollment is a **UI job on purpose**: GNOME has *Settings → System → Users →
Fingerprint Login*, Plasma 6 has *System Settings → Users → Fingerprint*, and both
talk to fprintd directly — so `ucli fingerprint` installs and starts the daemon and
tells you where to click, instead of driving `fprintd-enroll` over your shoulder.
Desktops older than that (Plasma 6.0, Hyprland, anything else) have no page, which
is what `--enroll` is for.

The **`--pam`** flag is opt-in for a reason. It appends
`auth sufficient pam_fprintd.so` after the `pam_unix.so` line in
`/etc/pam.d/system-auth` — the order that keeps your password working and adds the
finger as an alternative. It copies the file to `system-auth.ucli-backup` first and
refuses to touch anything if it cannot find that line. Test it by locking the
screen with a root shell open, not by logging out.

### Firmware

`fwupd` is in `SYSTEM_CORE_TOOLS`, so it arrives with `base` (`ucli setup-system`):
GNOME's Firmware panel talks to it over D-Bus and needs no service of its own.
On the command line, and worth running after a BIOS/firmware update:

```bash
fwupdmgr get-devices           # what it can see (UEFI dbx, SSD/EC firmware, docks)
sudo fwupdmgr refresh --force  # pull the latest metadata from LVFS
sudo fwupdmgr get-updates      # what is pending
sudo fwupdmgr update           # apply (some updates only land on reboot)
```

Arch does not enable the LVFS metadata download by itself; `refresh` is what
fetches it. Firmware that LVFS does not carry (most laptop ECs, some docks) is
still a vendor/manual job — `ucli bios` reboots straight into the firmware UI
for that.

`ucli update` warns about foreign (AUR / locally built) packages and asks
before upgrading — the Arch analogue of `ujust update` refusing to run while
the bootc image has layered packages. `UCLI_YES=1` (or a non-interactive run)
proceeds silently.

Six shared helpers live in one place — `~/.local/share/ucli/scripts/lib/`. The
first two were ported from Bluefin; `common.sh` exists because the same four-line
function had been copy-pasted into eight scripts:

| File | What it gives you |
|---|---|
| `lib/ui.sh` | the whole interactive grammar: `ui_title` / `ui_rule` / `ui_box` / `ui_summary`, `ui_choose` (single), `ui_choose_multi` (sections + preselect), `ui_confirm`, `ui_step` (block progress bar with ✓/✗) |
| `lib/version-script.sh` | `vs_check` / `vs_commit` / `vs_list` — a versioned hook gate: a step runs once per version token (counter or content hash) and is retried until it succeeds |
| `lib/detect.sh` | machine facts as functions — `detect_distro`, `detect_desktop`, `detect_root_fstype`, `detect_snapper_root`, `detect_limine`, … — so no script re-implements `/etc/os-release` parsing |
| `lib/aur.sh` | `aur_exists` / `aur_provides` — AUR lookups (RPC, `git ls-remote` fallback, `provides=` resolution) shared by `install-packages.sh` and `validate-packages.sh`, which each used to carry their own copy |
| `lib/firefox.sh` | `fx_profile_root` / `fx_profile_dirs` / `fx_config_dir` — the 147+ `~/.config/mozilla/firefox` vs `~/.mozilla/firefox` split, in one place |
| `lib/common.sh` | `as_root` (sudo only when needed), `have`, `confirm` (honours the caller's `--yes`) — sourced by the service installers, `doctor`, `config-audit`, `uninstall` and `arch-snapper-limine` |

The libs live next to the scripts, not in `~/.config`, so a script running under
sudo loads them from its own path (`source "$(dirname "$0")/../lib/ui.sh"`);
that is why `ucli devmode`, `ucli setup-desktop --choose`, `ucli debloat-desktop`,
`ucli mirrors`, `ucli update` and the `ucli` chooser all look and behave the
same. Two rules for new menus: menu labels carry no commas (gum's `--selected`
is comma-separated) and a category is a left-hand column, never a row you can
tick (gum cannot render an untogglable row).

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

One script does the offline checks, and it runs in both places: against the repo
checkout (CI) and against a deployed home (`ucli check`).

```bash
ucli check                      # deployed: ~/.local/share/ucli/scripts/check/check.sh
bash ~/.local/share/ucli/scripts/check/check.sh ~/dots   # or any checkout
```

| Check | Catches |
|---|---|
| `bash -n` on every shipped script | syntax errors in code that only runs during setup |
| `zsh -n` on `~/.zshrc`, `pre-omz.zsh`, `conf.d/*.zsh` | a broken shell config you would only notice by opening a terminal |
| `just --list` | recipes that silently degrade to line-wise mode (a comment above the `#!` body) |
| array consistency | a package array renamed in `packages.bash` but not in `validate-packages.sh`/`install-packages.sh` — `SHELL_DEPS` → `SHELL_TOOLS` was exactly this bug |
| hidden prompts | an interactive command (`chsh`, `passwd`, `ssh-keygen`, `ssh-add`) with `2>/dev/null`: their password prompt *is* stderr, so redirecting it turns them into a silent hang — `chsh -s … 2>/dev/null` did exactly that at the end of the shell step |
| exit codes | a script that ends on a bare `(( … )) && …` / `[[ … ]] && …`: mid-script that is exempt from `set -e`, as the last line its false test *becomes* the script's exit status — `install-flatpaks.sh base` failed `ucli setup-system` that way, silently, after the packages were installed |
| stale verbs | a doc, comment or `echo` that still names a recipe which no longer exists (the `gnome` menu and `devbox-shell` verbs were both removed while docs kept naming them) — the prose allowlist in `check.sh` is deliberately tiny |
| `shellcheck --severity=warning` | real shell bugs and the unused-state / word-splitting class, when it is installed |

CI runs the same script from `.github/workflows/check.yml` on every push and PR
(Ubuntu, with `just`, `zsh` and `shellcheck` installed).

`ucli doctor` is the runtime counterpart
(`~/.local/share/ucli/scripts/check/doctor.sh`). It walks the same layers the
setup does and reports OK/MISSING/WARN per item: dotfiles (`chezmoi diff` empty,
justfile, `.bash_profile` PATH, `.zshrc`, `plugins.txt`); shell (parses, login
shell, oh-my-zsh, starship + `starship.toml`, plugins against `plugins.txt`,
`local.zsh`, the available flags, motd); ucli runtime (just/gum/pipx/gext/AUR
helper/flatpak); apps (Firefox profile + Betterfox, snapper config, GNOME
enabled-extension count); the personal overlay (`packages.local.bash`); the
archinstall baseline (bluez, pipewire, wireplumber, cups, power-profiles-daemon —
reported, never installed); committed gates; dev box. Exit status is 1 when
anything is MISSING; warnings alone do not fail it.

On a console-only box (no desktop yet) the shell-tier items — `.zshrc`,
`plugins.txt`, zsh, oh-my-zsh, starship — print as `—` with "expected on a
console-only box" instead of MISSING: `.chezmoiignore` holds them back on purpose
until `ucli setup-system` installs the programs they belong to.

The heavier, network-bound checks stay manual:

```bash
ucli validate                   # every package array against pacman/AUR
chezmoi cd && chezmoi diff
chezmoi execute-template < run_after_95-zsh-plugins.sh.tmpl | sed -n '1,8p'
```
