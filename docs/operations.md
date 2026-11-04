# Day to day

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
| `shellcheck --severity=error` | real shell bugs, when it is installed |

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
