# Packages, shell and apps

## ucli

```bash
ucli                      list every recipe (hidden `_`-prefixed ones omitted)
ucli --choose             picker (gum → fzf → plain select)
ucli usage                the short version of the setup flow
ucli profile              configured + detected profile facts
ucli doctor               health check: dotfiles, shell, tools, apps, gates, dev box
ucli check                offline static checks (syntax, just, package arrays)
ucli validate             package array check against pacman/AUR (network)
ucli state                committed version gates + devmode marker
ucli inventory            package/app/settings inventory
```

## Install

```bash
ucli setup-system         first-machine profile (packages + basic setup)
ucli cli                  shell tier: oh-my-zsh + plugins + zsh login shell + cosmetics
ucli devmode              developer wizard — plumbing, apps, dev box (re-runnable)
ucli gaming               gaming profile
ucli apps                 desktop apps, flatpaks, Firefox extensions (+ your overlay)
```

Every package list lives in `private_dot_config/ucli/packages.bash`:

| Tier | What it is | Installed by |
|---|---|---|
| `UCLI_RUNTIME` | what ucli itself needs: `gum` (menus, wizard) and `python-pipx` (gext) | `base` → `ucli setup-system`, `ucli setup-desktop` |
| `DESKTOP_BROWSER` | `firefox` — the browser the dotfiles configure. The config ships with the browser: `setup-desktop` creates the profile, copies the Betterfox `user.js` and (on GNOME) installs firefox-gnome-theme before its snapshot. Only the extension list is opted in later, via `ucli apps` | `desktop` mode → `ucli setup-system`/`setup-desktop`; `ucli apps` always, even when no desktop is detected |
| `DESKTOP_TERMINAL_GNOME` | `ghostty` — GTK4, already inside the Adwaita stack | same, plus `ucli apps` when the desktop is known |
| `DESKTOP_TERMINAL_HYPRLAND` | `ghostty` — native wlroots/Wayland client, honours window rules; `kitty` is no longer in `DESKTOP_HYPRLAND_BASE` | same, plus `ucli apps` when the desktop is known |
| `DESKTOP_TERMINAL_KDE` | `kwi` — KDE's new terminal (Qt Quick + Kirigami, GPU-rendered, libghostty-vt underneath); AUR-only today as `kwi-git`, so the AUR resolver maps the name, and Konsole from the `plasma` group is the safety net | same, plus `ucli apps` when the desktop is known |
| `SHELL_TOOLS` | the shell tier: `zsh`, `git`, `curl`, `starship` — what `install-shell.sh` needs to build oh-my-zsh, clone the plugins and initialise the prompt | `ucli setup-system`/`setup-desktop` and `ucli cli` |
| `CLI` | shell cosmetics on top: `eza bat zoxide atuin tealdeer glow fzf` | `ucli cli` |
| `DEV_CLI` | engineering plumbing: `jq yq ripgrep ugrep fd tree duf direnv mise lazygit vim tmux shfmt` — needed the moment you touch a repo (`neovim` is a personal pick, see the overlay below) | `ucli devmode` |
| `DEV` | the heavy stack: `base-devel podman distrobox docker* podman-desktop vscodium-bin vscodium-bin-marketplace` | `ucli devmode` (`--force` bypasses the role check) |
| `SYSTEM_MEDIA_CODECS` | `gst-plugins-good bad ugly`, `gst-libav`, `ffmpeg` — archinstall installs none of them, and GNOME's own video apps only pull `gst-plugins-base` | `base` → `ucli setup-system` |
| `HARDWARE_FINGERPRINT` / `HARDWARE_TOUCHPAD` | `fprintd` when a reader is found (USB ids 138a/06cb/27c6/08ff/0483), `libinput-tools` when a touchpad or trackpoint is | `base`, decided by `lib/detect.sh` — never on hardware that does not need it |

`ugrep` ships as its own command (`ug`), not as an alias for `grep`: it is
recursive by default and searches inside archives, so swapping it under `grep`
would change what your typed pipelines do.

`dev` mode selects `dev-cli` first, so the heavy stack always arrives with its
plumbing. `ucli cli` runs `install-shell.sh` first (`SHELL_TOOLS`: zsh, git,
curl, starship), so it works on a machine that never ran `ucli setup-system`.
`ucli full-profile` (a.k.a. `install-packages.sh full`) is
`base + cli + dev + gaming`.

**The terminal follows the desktop, the browser does not.** `select_essentials`
in `install-packages.sh` adds `DESKTOP_BROWSER` plus the one
`DESKTOP_TERMINAL_<DE>` array, so GNOME and Hyprland get ghostty, KDE gets kwi,
and a machine with no desktop gets neither. `~/.config/ghostty` and
`~/.config/kitty` follow the same rule on the dotfiles side (`.chezmoiignore`
asks `lookPath`), so you never end up with a terminal config for a terminal you
do not have. Want one terminal everywhere? Point all three arrays at it.

`base` does not install a desktop: `setup-desktop.sh` owns that step, so the
skip/replace matrix, firefox + terminal, the extension set and the snapshot all
happen in one place. `install-packages.sh full` still includes `desktop`.

`base` installs the zsh *binary* (it is in `BOOTSTRAP`, and the dev box and the
dotfiles expect it) but takes no opinion on your login shell. The bootstrap
script in `install.sh` deliberately does not: a console-only box gets git,
chezmoi and just, and nothing else until `ucli setup-system` runs — oh-my-zsh,
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
(`shell`, `paru`, `full-setup`, …).

### Per-machine overrides

Every tool block in `~/.config/zsh/conf.d` sits behind a flag, all defaulting to
on — `0` turns just that block off, `1` or unset keeps it:

```
UCLI_SHELL_ENABLE_EZA  _BAT  _FD  _RG  _DUF  _TLDR  _GLOW
UCLI_SHELL_ENABLE_ATUIN  _DIRENV  _ZOXIDE  _MISE
```

Put them — plus your own aliases and exports — in `~/.config/zsh/local.zsh`:

```bash
cp ~/.config/zsh/local.zsh.example ~/.config/zsh/local.zsh
```

`~/.zshrc` sources it *before* `conf.d/`, so your values win; it is not
chezmoi-managed, so `chezmoi apply` never touches it. The point is one machine
opting out of one behaviour (keep GNU `ls`, disable `atuin` while debugging
history) without forking the repo. A flag only gates the aliases — the binary
stays installed and callable by its own name. `ucli doctor` lists the flags and
whether `local.zsh` exists.

### Personal picks (the overlay)
`packages.bash` holds the opinionated sets. Anything that is a taste, an account,
a subscription or one specific piece of hardware goes into
`~/.config/ucli/packages.local.bash` instead:

```bash
cp ~/.config/ucli/packages.local.bash.example ~/.config/ucli/packages.local.bash
```

| Array | Installed by | Holds |
|---|---|---|
| `PERSONAL_PKGS` | `ucli apps` | pacman/AUR packages (password manager, torrent client, `neovim`, …) |
| `PERSONAL_DEV` | `ucli devmode` | extra dev packages on top of `DEV_CLI` + `DEV` |
| `PERSONAL_FLATPAKS` | `ucli apps` | flatpak IDs (Spotify, Obsidian, Bottles, wallpaper tools, …) |
| `PERSONAL_GNOME_EXTENSIONS` | `ucli setup-extensions` (`personal` set) | `"PK:UUID"` pairs from extensions.gnome.org |

The same idea as `~/.config/zsh/local.zsh`: never chezmoi-managed, never
required, and read only if it exists. The Firefox equivalents are files —
`~/.config/ucli/firefox/personal-extensions.txt` and `personal-dev-extensions.txt`
— because the repo's `extensions.txt` ships empty: which add-ons you run is not a
default anyone should inherit. `ucli doctor` reports whether the overlay is in
play.

### Reruns and gates

Steps that are slow or hit the network are gated by a content hash
(`lib/version-script.sh`); everything else is a cheap idempotent no-op:

| Step | Token | Re-runs when |
|---|---|---|
| GNOME extension sets (`system`, `personal`) | hash of `packages.bash` (+ `packages.local.bash` for `personal`) | the extension lists change |
| Betterfox `user.js` | hash of `~/.config/ucli/firefox/user.js` | you edit `user.js` |
| VSCodium extensions | hash of `extensions.txt` | the list changes |

`--force` redoes the work anyway (`ucli setup-extensions --force`,
`ucli setup-desktop --force` / `ucli apps --force`, `ucli vscodium-extensions --force`). A gate is only
committed after the step succeeded, so a failed run is retried next time instead
of being skipped forever. `ucli state` prints the committed gates, and
`ucli doctor` lists them next to the rest of the machine's health.
