# Apply the curated GNOME defaults (`gnome-defaults.sh`): the values Bluefin ships
# in its gschema override — dock as a fixed bar with dots, popup blur, Super/Alt-Tab
# split, weekday in the clock, no hot corners, folders-first file choosers, and the
# Nautilus "Open in terminal" wired to ghostty — written as *user* settings.
#
#   ucli gnome-defaults            apply what is still at its schema default
#   ucli gnome-defaults --status   what is set, what is yours, what is missing
#   ucli gnome-defaults --force    also overwrite values you set yourself
#   ucli gnome-defaults --dry-run  print the gsettings calls, write nothing
[group('GNOME')]
gnome-defaults *ARGS:
    # Bluefin's curated GNOME defaults, per user (--status / --force / --dry-run)
    @~/.local/share/ucli/scripts/install/gnome-defaults.sh {{ARGS}}

# Install the adw-gtk3 runtime extensions from Flathub, so Flatpak GTK3 apps use the
# same theme as the host. Flatpak can add them by itself on the next `flatpak
# install`/`update` (it reads the host's gtk-theme key); doing it here means they are
# there before the first Flatpak app runs.
#
#   ucli flatpak-theme            this user's Flatpak installation (default)
#   ucli flatpak-theme --system   system-wide (needs root; apps must be too)
#   ucli flatpak-theme --dry-run  print the flatpak commands
[group('GNOME')]
flatpak-theme *ARGS:
    # adw-gtk3 GTK theme extensions for Flatpak (--system / --dry-run)
    @~/.local/share/ucli/scripts/install/install-flatpak-gtk-theme.sh {{ARGS}}

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
    failed=()
    # The machinery, not just the extensions: Extension Manager (the GUI that
    # browses, enables and tunes them) plus the repo-packaged extensions. Installing
    # extensions with no way to see or switch them off is half the job.
    if ! "$script_dir/install-packages.sh" gnome-extensions; then
        printf '✗ could not install the extension packages (Extension Manager)\n' >&2
        failed+=(packages)
    fi
    if ! command -v gext >/dev/null 2>&1 && [[ -x "$script_dir/install-gnome-extensions-cli.sh" ]]; then
    "$script_dir/install-gnome-extensions-cli.sh"
    fi
    # --force bypasses the versioned gate, which otherwise skips a set whose
    # extension lists (packages.bash) have not changed since the last run
    force_args=()
    for arg in "$@"; do
        [[ "$arg" == "--force" ]] && force_args=(--force)
    done
    # Each set is named when it fails: "recipe 'setup-extensions' failed on line
    # 22" tells you nothing about which half of it broke. The set scripts already
    # print what is missing and that nothing was recorded, so this only adds the
    # name and keeps going (a broken personal overlay must not hide the system set).
    run_set() {
        local which="$1"
        if "$script_dir/install-gnome-extension-set.sh" "$which" ${force_args[@]+"${force_args[@]}"}; then
            return 0
        fi
        printf '✗ the %s GNOME extension set is incomplete (see above)\n' "$which" >&2
        failed+=("$which")
    }
    # managed: the repo's set (packages.bash GNOME_MANAGED_EXTENSIONS) plus the
    # Gradia Capture build; `system` is still accepted as a legacy alias by the
    # script, but this is the name that means what it does
    run_set managed
    # personal: PERSONAL_GNOME_EXTENSIONS from packages.local.bash, if that exists
    run_set personal
    # Their settings, immediately: enabling dash-to-dock and blur-my-shell without
    # the defaults leaves an unstyled bar with square indicators, which is not what
    # the set is for. `gnome-defaults` skips keys whose schema is missing, so it is
    # safe to run even when a set above failed — and it must not hide that failure,
    # which is why it runs before the check and only warns.
    if [[ -x "$script_dir/gnome-defaults.sh" ]]; then
        "$script_dir/gnome-defaults.sh" || printf 'warning: some GNOME defaults were not applied; re-run: ucli gnome-defaults\n' >&2
    fi
    if (( ${#failed[@]} )); then
        printf 'error: GNOME extensions incomplete: %s\n' "${failed[*]}" >&2
        printf '  retry: ucli setup-extensions --force\n' >&2
        exit 1
    fi
    printf 'ok: extensions installed and enabled with their settings, Extension Manager available (log out/in if the shell has not reloaded)\n'
