# Distrobox `dev` container: lifecycle + the Remote-SSH bootstrap fix.
#
# Box lifecycle IS managed in this source tree — nothing needs to be recreated
# by hand, and `chezmoi apply` reconciles an existing box in place:
#   manifest     -> private_dot_config/distrobox/dev.ini
#   provisioner  -> private_dot_config/distrobox/provision-dev.sh
#   tunables     -> private_dot_config/distrobox/devbox.env   (node/php channel)
#   reconcile    -> private_dot_local/share/ucli/scripts/devbox/executable_devbox-reconcile.sh
#   (no hook)    -> chezmoi ships these files only; nothing in run_* starts,
#                   stops or enters a container
#   compose file -> private_dot_config/dev-services/compose.yml
#   vscodium ext -> private_dot_local/share/ucli/scripts/install/executable_install-vscodium-extensions.sh
#
# The reconcile reads the Debian version from `image=debian:<N>` in dev.ini and
# the box name from its `[section]`, so dev.ini is the single source of truth.

# Enter the box. `ucli` on its own is the menu; this is the one you type daily.
[group('Dev box')]
devbox:
    #!/usr/bin/env bash
    # Enter the `dev` container, creating it first from dev.ini if it doesn't
    # exist yet. If dev.ini is missing, fall back to distrobox's default image
    # (fedora-toolbox) — that is the intentional no-config route.
    set -euo pipefail
    . "$HOME/.local/share/ucli/scripts/lib/common.sh"

    reconcile="$HOME/.local/share/ucli/scripts/devbox/devbox-reconcile.sh"

    have distrobox || {
      ui_fail "distrobox is not installed (ucli devmode installs it)"
      exit 1
    }

    if [[ -f "$HOME/.config/distrobox/dev.ini" ]]; then
      # Ask the reconcile about the box instead of guessing: 0 = there and
      # running, 3 = there but stopped, 1 = not there yet.
      box_state=0
      "$reconcile" --exists || box_state=$?
      case "$box_state" in
        0)
          # The normal path. Silent, because the reconcile only does work when
          # dev.ini / the provisioner changed.
          QUIET=1 "$reconcile" || true
          ;;
        3)
          # After a reboot: the reconcile starts the container, which is a
          # second or two but not instant, so say what the pause is.
          ui_note "starting the dev box"
          QUIET=1 "$reconcile" || true
          ;;
        *)
          # First run. Say so *before* the slow part: the image pull and the
          # Debian provisioning that follow take minutes, and a recipe that
          # prints nothing for minutes reads as a hang. It is not a hang:
          # ctrl-c is safe, the reconcile is idempotent, the next run resumes.
          ui_rule "Creating the dev box"
          ui_note "first run only: Debian image pull + provisioning, a few minutes"
          ui_note "progress is printed below · ctrl-c is safe, re-run to resume"
          "$reconcile"
          ;;
      esac
    fi

    exec distrobox enter dev

# Throwaway "pet" container from a stock image (ubuntu, fedora, wolfi, debian,
# arch, alpine) — what Bluefin ships preconfigured, as one command. The `dev`
# box above stays the provisioned one; these are for a quick other-distro shell.
# Create a throwaway container from a stock distro image.
[group('Dev box')]
devbox-create *ARGS:
    # ucli devbox-create ubuntu [name]   •   --list shows the images
    @~/.local/share/ucli/scripts/devbox/devbox-create.sh {{ARGS}}

# Silent and instant when dev.ini / provision-dev.sh / devbox.env are unchanged.
# Create or update the box: Debian base + nvm Node + sury PHP + composer.
[group('Dev box')]
devbox-reconcile:
    @~/.local/share/ucli/scripts/devbox/devbox-reconcile.sh

# The container is discarded; $HOME, ~/.nvm, ~/.vscode-server and your repos
# survive, and provisioning runs automatically afterwards.
# Rebuild the container to apply image/volume/init_hooks changes (Debian bump).
[group('Dev box')]
devbox-recreate:
    #!/usr/bin/env bash
    set -euo pipefail
    DISTROBOX_RECREATE=1 exec "$HOME/.local/share/ucli/scripts/devbox/devbox-reconcile.sh"

# Versions inside the box (what the rest of the tooling assumes).
[private]
devbox-versions:
    @distrobox enter dev -- bash -lc 'printf "debian   %s\n" "$(cat /etc/debian_version)"; printf "node     %s\n" "$(node -v 2>/dev/null || echo MISSING)"; printf "npm      %s\n" "$(npm -v 2>/dev/null || echo MISSING)"; printf "php      %s\n" "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"; printf "composer %s\n" "$(composer --version 2>/dev/null | head -1)"; printf "docker   %s\n" "$(docker --version 2>/dev/null | head -1)"'

# Provisioning log from the last create/boot (apt, nvm, php, plugin warnings).
[private]
devbox-log:
    @distrobox enter dev -- sudo tail -n 100 /var/log/devbox-provision.log



# Walks auth -> login shell -> prereqs -> the exact `bash -l` pipeline.
# Diagnose why Remote-SSH cannot bootstrap its server in the box.
[private]
devbox-vscode-doctor *ARGS:
    ~/.local/share/ucli/scripts/devbox/devbox-vscode-doctor.sh {{ARGS}}

# and prove the host-spawn guard fixes it before you install it.
# Bisect the `bash -l` profile chain for the file that eats stdin.
[private]
devbox-vscode-bisect *ARGS:
    ~/.local/share/ucli/scripts/devbox/devbox-vscode-bisect.sh {{ARGS}}