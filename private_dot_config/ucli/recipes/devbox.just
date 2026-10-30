# Distrobox `dev` container: lifecycle + the Remote-SSH bootstrap fix.
#
# Box lifecycle IS managed in this source tree — nothing needs to be recreated
# by hand, and `chezmoi apply` reconciles an existing box in place:
#   manifest     -> private_dot_config/distrobox/dev.ini
#   provisioner  -> private_dot_config/distrobox/executable_provision-dev.sh
#   tunables     -> private_dot_config/distrobox/devbox.env   (node/php channel)
#   reconcile    -> private_dot_config/ucli/scripts/devbox/executable_devbox-reconcile.sh
#   hook         -> run_after_92-distrobox-dev.sh  (same script, every apply)
#   compose file -> private_dot_config/dev-services/compose.yml
#   vscodium ext -> private_dot_config/ucli/scripts/install/executable_install-vscodium-extensions.sh
#
# The reconcile reads the Debian version from `image=debian:<N>` in dev.ini and
# the box name from its `[section]`, so dev.ini is the single source of truth.

# Open an interactive shell inside dev.
devbox-shell:
    @distrobox enter dev

# Create or update the box: Debian base + nvm Node + sury PHP + composer.
# Silent and instant when dev.ini / provision-dev.sh / devbox.env are unchanged.
devbox-reconcile:
    @~/.config/ucli/scripts/devbox/devbox-reconcile.sh

# Rebuild the container to apply image/volume/init_hooks changes (Debian bump).
# The container is discarded; $HOME, ~/.nvm, ~/.vscode-server and your repos
# survive, and provisioning runs automatically afterwards.
devbox-recreate:
    #!/usr/bin/env bash
    set -euo pipefail
    DISTROBOX_RECREATE=1 exec "$HOME/.config/ucli/scripts/devbox/devbox-reconcile.sh"

# Versions inside the box (what the rest of the tooling assumes).
devbox-versions:
    @distrobox enter dev -- bash -lc 'printf "debian   %s\n" "$(cat /etc/debian_version)"; printf "node     %s\n" "$(node -v 2>/dev/null || echo MISSING)"; printf "npm      %s\n" "$(npm -v 2>/dev/null || echo MISSING)"; printf "php      %s\n" "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"; printf "composer %s\n" "$(composer --version 2>/dev/null | head -1)"; printf "docker   %s\n" "$(docker --version 2>/dev/null | head -1)"'

# Provisioning log from the last create/boot (apt, nvm, php, plugin warnings).
devbox-log:
    @distrobox enter dev -- sudo tail -n 100 /var/log/devbox-provision.log

# Re-run provisioning in place, without recreating the container.
devbox-reprovision:
    @distrobox enter dev -- sudo DEVBOX_FORCE=1 bash ~/.config/distrobox/provision-dev.sh

# Print the exact command assemble would run for this manifest.
devbox-dry-run:
    #!/usr/bin/env bash
    set -euo pipefail
    distrobox assemble create --dry-run --file "$HOME/.config/distrobox/dev.ini"

# Diagnose why Remote-SSH cannot bootstrap its server in the box.
# Walks auth -> login shell -> prereqs -> the exact `bash -l` pipeline.
devbox-vscode-doctor *ARGS:
    ~/.config/ucli/scripts/devbox/devbox-vscode-doctor.sh {{ARGS}}

# Bisect the `bash -l` profile chain for the file that eats stdin,
# and prove the host-spawn guard fixes it before you install it.
devbox-vscode-bisect *ARGS:
    ~/.config/ucli/scripts/devbox/devbox-vscode-bisect.sh {{ARGS}}
