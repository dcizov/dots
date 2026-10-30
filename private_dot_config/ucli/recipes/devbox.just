# Distrobox `dev` container: lifecycle + the Remote-SSH bootstrap fix.
#
# Box lifecycle IS managed in this source tree — nothing needs to be recreated
# by hand, and `chezmoi apply` reconciles an existing box in place:
#   manifest     -> private_dot_config/distrobox/dev.ini
#   provisioner  -> private_dot_config/distrobox/executable_provision-dev.sh
#   tunables     -> private_dot_config/distrobox/devbox.env   (node/php channel)
#   reconcile    -> private_dot_config/ucli/scripts/devbox/executable_devbox-reconcile.sh
#   (no hook)    -> chezmoi ships these files only; nothing in run_* starts,
#                   stops or enters a container
#   compose file -> private_dot_config/dev-services/compose.yml
#   vscodium ext -> private_dot_config/ucli/scripts/install/executable_install-vscodium-extensions.sh
#
# The reconcile reads the Debian version from `image=debian:<N>` in dev.ini and
# the box name from its `[section]`, so dev.ini is the single source of truth.

# Everything the box can do, in one menu (fzf → gum → plain select).
[group('Dev box')]
devbox:
    #!/usr/bin/env bash
    set -euo pipefail
    . "$HOME/.config/ucli/scripts/lib/choose.sh"
    ucli_bin="$(command -v ucli || printf '%s' "$HOME/.local/bin/ucli")"
    action="$(ui_choose 'dev box' \
      'reconcile|create or update the box — instant no-op when nothing changed' \
      'shell|open an interactive shell inside dev' \
      'versions|debian / node / npm / php / composer inside the box' \
      'log|tail /var/log/devbox-provision.log from the last run' \
      'reprovision|re-run provisioning, keep the container' \
      'recreate|rebuild the container (image / volumes / init_hooks)' \
      'dry-run|print the distrobox-assemble command for this manifest' \
      'vscode-doctor|diagnose why Remote-SSH cannot bootstrap in the box' \
      'vscode-bisect|find the profile file that eats stdin')" || exit 0
    case "$action" in
      reconcile)     exec "$ucli_bin" devbox-reconcile ;;
      shell)         exec "$ucli_bin" devbox-shell ;;
      versions)      exec "$ucli_bin" _devbox-versions ;;
      log)           exec "$ucli_bin" _devbox-log ;;
      reprovision)   exec "$ucli_bin" _devbox-reprovision ;;
      recreate)      exec "$ucli_bin" _devbox-recreate ;;
      dry-run)       exec "$ucli_bin" _devbox-dry-run ;;
      vscode-doctor) exec "$ucli_bin" _devbox-vscode-doctor ;;
      vscode-bisect) exec "$ucli_bin" _devbox-vscode-bisect ;;
    esac

# Open an interactive shell inside dev.
[group('Dev box')]
devbox-shell:
    @distrobox enter dev

# Create or update the box: Debian base + nvm Node + sury PHP + composer.
# Silent and instant when dev.ini / provision-dev.sh / devbox.env are unchanged.
[group('Dev box')]
devbox-reconcile:
    @~/.config/ucli/scripts/devbox/devbox-reconcile.sh

# The container is discarded; $HOME, ~/.nvm, ~/.vscode-server and your repos
# survive, and provisioning runs automatically afterwards.
# Rebuild the container to apply image/volume/init_hooks changes (Debian bump).
_devbox-recreate:
    #!/usr/bin/env bash
    set -euo pipefail
    DISTROBOX_RECREATE=1 exec "$HOME/.config/ucli/scripts/devbox/devbox-reconcile.sh"

# Versions inside the box (what the rest of the tooling assumes).
_devbox-versions:
    @distrobox enter dev -- bash -lc 'printf "debian   %s\n" "$(cat /etc/debian_version)"; printf "node     %s\n" "$(node -v 2>/dev/null || echo MISSING)"; printf "npm      %s\n" "$(npm -v 2>/dev/null || echo MISSING)"; printf "php      %s\n" "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"; printf "composer %s\n" "$(composer --version 2>/dev/null | head -1)"; printf "docker   %s\n" "$(docker --version 2>/dev/null | head -1)"'

# Provisioning log from the last create/boot (apt, nvm, php, plugin warnings).
_devbox-log:
    @distrobox enter dev -- sudo tail -n 100 /var/log/devbox-provision.log

# Goes through the reconcile so it shares the flock, the init wait and the
# streamed output instead of starting a second apt run behind its back.
# Re-run provisioning in place, without recreating the container.
_devbox-reprovision:
    #!/usr/bin/env bash
    set -euo pipefail
    DEVBOX_FORCE=1 exec "$HOME/.config/ucli/scripts/devbox/devbox-reconcile.sh"

# Print the exact command assemble would run for this manifest.
_devbox-dry-run:
    #!/usr/bin/env bash
    set -euo pipefail
    distrobox assemble create --dry-run --file "$HOME/.config/distrobox/dev.ini"

# Walks auth -> login shell -> prereqs -> the exact `bash -l` pipeline.
# Diagnose why Remote-SSH cannot bootstrap its server in the box.
_devbox-vscode-doctor *ARGS:
    ~/.config/ucli/scripts/devbox/devbox-vscode-doctor.sh {{ARGS}}

# and prove the host-spawn guard fixes it before you install it.
# Bisect the `bash -l` profile chain for the file that eats stdin.
_devbox-vscode-bisect *ARGS:
    ~/.config/ucli/scripts/devbox/devbox-vscode-bisect.sh {{ARGS}}
