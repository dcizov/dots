# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A chezmoi source directory for Arch / CachyOS post-install setup (not an OS installer). It deploys dotfiles plus `ucli`, a `just` wrapper whose recipes drive bash scripts. Remote: `github.com/dcizov/dots`. User-facing docs live in `docs/` (start with `docs/getting-started.md`; `docs/operations.md` covers `check`/`doctor`).

## Commands

```bash
# Offline static checks — exactly what CI runs (bash -n, zsh -n, just --list,
# package-array consistency, stale `ucli <verb>` references, shellcheck -S warning)
bash private_dot_local/share/ucli/scripts/check/executable_check.sh "$PWD"

# Python tests (backup/inventory, using a temp restic repo and stubbed binaries)
python3 -B -m unittest discover -s tests -v
python3 -B -m unittest tests.test_backup.BackupTests.test_init_is_explicit_and_refuses_a_nonempty_directory

# List recipes straight from the source tree
just --justfile private_dot_config/ucli/justfile --list

# Preview / apply what chezmoi would deploy
chezmoi diff
chezmoi apply
```

CI (`.github/workflows/check.yml`) needs `just`, `zsh`, `shellcheck`, `restic`. CI runs Ubuntu's older shellcheck (0.9.x); the tree must be clean on both that and newer local versions.

## Architecture

**chezmoi naming is load-bearing.** `private_dot_config/x` → `~/.config/x`, `executable_foo.sh` → `foo.sh` (mode +x), `*.tmpl` are Go templates. Scripts call each other by *deployed* paths (`~/.local/share/ucli/scripts/install/install-shell.sh`), never by source paths. `run_once_*`, `run_onchange_*`, `run_after_*` at the root are chezmoi hooks. `run_onchange_after_90-ucli-install.sh.tmpl` re-runs whenever the hashes of the justfile and wrapper in its comment change.

**Two-epoch deploy, gated by `.chezmoiignore`.** The bootstrap (`install.sh`) only installs git/chezmoi/just and makes `ucli` work. `.chezmoiignore` uses `lookPath` on every apply, so program config (zsh, starship, ghostty, kitty, Firefox sources, distrobox) deploys only once that program is installed. `ucli setup-system` installs packages and then runs `chezmoi apply` again, which is when that config shows up. Anything that isn't a dotfile (docs, tests, README, install.sh, this file) must be listed in `.chezmoiignore`, or it will be deployed into `$HOME`. Machine data (`machine`, `desktop`, `terminal`, `role`, `gaming`) comes from the prompts in `.chezmoi.toml.tmpl`.

**ucli layers:**
- `private_dot_local/bin/executable_ucli` — thin `exec just --justfile ~/.config/ucli/justfile`. With no arguments it opens the gum menu (`scripts/system/ucli-menu.sh`).
- `private_dot_config/ucli/justfile` imports `recipes/*.just`. Recipes are one-liners that call a script, use `[group('…')]` for the menu, and use `[private]` for aliases. With `set ignore-comments`, comment lines in a recipe body describe it. A comment above a shebang body turns it into a line-wise recipe, which `check.sh` detects with `just --list`.
- `private_dot_config/ucli/packages.bash` — every package array (`UCLI_RUNTIME`, `SHELL_TOOLS`, `DESKTOP_*`, `CLI`, `DEV_CLI`, `DEV`, `GAMING`, …) plus machine settings such as the AUR helper. Per-machine overrides go in `packages.local.bash` (see the `.example`). `check.sh` fails if `validate-packages.sh` / `install-packages.sh` (`add_array X`) name an array that isn't defined here, so rename on both sides.
- `private_dot_local/share/ucli/scripts/<area>/` — the work, grouped as install, system, fix, check, devbox, backup, inventory. Shared code is in `scripts/lib/` and is sourced, never executed: `common.sh` (`as_root`, `have`; pulls in `ui.sh`), `detect.sh`, `aur.sh` (paru vs shelly), `firefox.sh`, `backup-paths.sh`, and `version-script.sh`.
- **Versioned gates** (`lib/version-script.sh`): `vs_check <name> <scope> <token>` / `vs_commit` store tokens under `~/.local/state/ucli/gates/`, so a step runs once per version (a bumped counter or a content hash) and commits only on success. Scripts run under sudo resolve the invoking user's home. Use these gates instead of ad-hoc marker files; `ucli state` shows them.

## Conventions enforced by `check.sh`

- Every `ucli <word>` mentioned in docs, recipes, scripts, or echo text must name a real recipe. When a recipe is renamed or removed, update its mentions everywhere. The prose allowlist in `check.sh` should stay short.
- A script must not end on a bare conditional (`(( x )) && …`), because a false test on the last line becomes the exit status.
- Never send an interactive command's stderr to `/dev/null` (for example `chsh`), because its prompt is printed on stderr.
- Every step must stay idempotent and safe to re-run on its own.
- On CachyOS, leave installer-owned pieces alone (Snapper/Limine, the DE). See `docs/distros.md`.

## Git

Conventional-commit subjects with a scope, e.g. `fix(backup): …`, `feat(gnome): …`. chezmoi `autoCommit`/`autoPush` are off.
