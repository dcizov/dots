# Install + enable the managed GNOME extension sets (idempotent, rerunnable).
[group('GNOME')]
setup-extensions *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    # Same work `ucli setup-desktop` does for gnome, runnable on its own: after a
    # `ucli debloat-desktop`, after an extension update, or on any GNOME machine.
    script_dir="$HOME/.local/share/ucli/scripts/install"
    # pipx + gum: gext is a pipx app, and the hooks below use gum for prompts
    "$script_dir/install-packages.sh" ucli-runtime || true
    if ! command -v gext >/dev/null 2>&1 && [[ -x "$script_dir/install-gnome-extensions-cli.sh" ]]; then
    "$script_dir/install-gnome-extensions-cli.sh"
    fi
    # --force bypasses the versioned gate, which otherwise skips a set whose
    # extension lists (packages.bash) have not changed since the last run
    force_args=()
    for arg in "$@"; do
        [[ "$arg" == "--force" ]] && force_args=(--force)
    done
    # system: repo-packaged defaults (caffeine, appindicator, …)
    "$script_dir/install-gnome-extension-set.sh" system ${force_args[@]+"${force_args[@]}"}
    # overrides: the gext-installed personal set (just-perfection, logo-menu, …)
    "$script_dir/install-gnome-extension-set.sh" overrides ${force_args[@]+"${force_args[@]}"}
    printf 'ok: extensions installed and enabled (log out/in if the shell has not reloaded)\n'

# GNOME menu. Use `ucli --choose` to pick a GNOME recipe interactively.
[group('GNOME')]
gnome:
    # apply managed GNOME dconf settings profile + re-enable extensions
    @~/.local/share/ucli/scripts/install/restore-gnome-settings.sh

# Analyze GNOME package/extension state.
_analyze:
    @~/.local/share/ucli/scripts/gnome/gnome-analyze.sh

# Backup GNOME settings.
_settings-backup:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh backup

# Restore GNOME Shell settings.
_restore-shell dir:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh restore-shell "{{dir}}"

# Restore GNOME extension settings.
_restore-extensions dir:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh restore-extensions "{{dir}}"

# Restore GNOME desktop settings.
_restore-desktop dir:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh restore-desktop "{{dir}}"


