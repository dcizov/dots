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
    # Each set is named when it fails: "recipe 'setup-extensions' failed on line
    # 22" tells you nothing about which half of it broke. The set scripts already
    # print what is missing and that nothing was recorded, so this only adds the
    # name and keeps going (a broken personal overlay must not hide the system set).
    failed=()
    run_set() {
        local which="$1"
        if "$script_dir/install-gnome-extension-set.sh" "$which" ${force_args[@]+"${force_args[@]}"}; then
            return 0
        fi
        printf '✗ the %s GNOME extension set is incomplete (see above)\n' "$which" >&2
        failed+=("$which")
    }
    # system: the opinionated layout set (dash-to-dock, blur-my-shell, gsconnect,
    # search-light, copyous) + the repo-packaged ones (caffeine, appindicator)
    run_set system
    # personal: PERSONAL_GNOME_EXTENSIONS from packages.local.bash, if that exists
    run_set personal
    if (( ${#failed[@]} )); then
        printf 'error: GNOME extensions incomplete: %s\n' "${failed[*]}" >&2
        printf '  retry: ucli setup-extensions --force\n' >&2
        exit 1
    fi
    printf 'ok: extensions installed and enabled (log out/in if the shell has not reloaded)\n'
