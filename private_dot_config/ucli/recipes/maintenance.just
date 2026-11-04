# Day-to-day maintenance, mirroring the useful half of Bluefin's ujust:
#
#   ujust update          -> ucli update
#   ujust clean-system    -> ucli clean-system   (dangling containers only)
#   ujust device-info     -> ucli report         (written to a file, no pastebin)
#   ujust logs-this-boot  -> ucli logs           (menu: this/last boot, devbox)
#   ujust bios, bios-info -> ucli bios, ucli bios-info
#   ujust changelogs      -> ucli changelogs     (from /var/log/pacman.log)
#   ujust check-local-overrides -> ucli config-audit (.pacnew + pacman -Qkk)
#
# Deliberately NOT ported: toggle-updates / rebase-helper / powerwash (bootc
# image concepts), enroll-secure-boot-key (ublue/Nvidia specific), benchmark and
# check-idle-power-draw (need stress-ng/powerstat), toggle-iwd / toggle-tpm2
# (rewrite the network and disk stack; do those by hand).

# Update everything: pacman, AUR, flatpaks, mise runtimes, then the dev box.
[group('Maintenance')]
update:
    #!/usr/bin/env bash
    # full system upgrade: pacman + AUR + flatpaks + mise + dev box
    set -uo pipefail
    . "$HOME/.local/share/ucli/scripts/lib/ui.sh"
    have() { command -v "$1" >/dev/null 2>&1; }

    # Guard, ported from `ujust update`: Bluefin refuses to update while the
    # image has layered packages, because that breaks its zero-maintenance
    # promise. The Arch equivalent of "layered" is foreign (AUR / locally built)
    # packages: they can need a rebuild or an upstream fix mid-upgrade, so show
    # them first and ask. UCLI_YES=1 (or a non-interactive run) proceeds.
    if have pacman; then
      foreign="$(pacman -Qm 2>/dev/null || true)"
      if [ -n "$foreign" ]; then
        n=$(printf '%s\n' "$foreign" | wc -l | tr -d ' ')
        ui_rule "foreign / AUR packages: $n"
        printf '%s\n' "$foreign" | awk 'NR<=10 { printf "    %s\n", $0 }'
        if [ "$n" -gt 10 ]; then printf '    … and %s more\n' "$((n - 10))"; fi
        printf '    Not from the official repos: AUR rebuilds are your responsibility.\n'
        if [ "${UCLI_YES:-0}" != 1 ] && [ -t 0 ]; then
          ui_confirm "Continue with the upgrade?" || { printf 'aborted.\n'; exit 1; }
        fi
      fi
    fi

    ui_rule "pacman: system upgrade"
    sudo pacman -Syu --noconfirm || true

    if have paru; then
    ui_rule "paru: AUR upgrades"
    paru -Sua --noconfirm || printf 'paru: nothing to do, or it failed\n' >&2
    elif have yay; then
    ui_rule "yay: AUR upgrades"
    yay -Sua --noconfirm || printf 'yay: nothing to do, or it failed\n' >&2
    fi

    if have flatpak; then
    ui_rule "flatpak: updates"
    flatpak update -y || true
    fi

    if have mise; then
    ui_rule "mise: runtimes"
    mise upgrade || true
    fi

    ui_rule "dev box"
    if [[ -x "$HOME/.local/share/ucli/scripts/devbox/devbox-reconcile.sh" ]]; then
    "$HOME/.local/share/ucli/scripts/devbox/devbox-reconcile.sh" || true
    else
    ui_rule "dev box: skipped (devbox-reconcile.sh not found)"
    fi

    ui_rule "done"
    printf 'A reboot is only needed for kernel/driver updates.\n'

# Named volumes are NEVER touched — dev_pgdata / dev_mysql hold your databases.
# Reclaim space: dangling images, unused flatpaks, old package cache.
[group('Maintenance')]
clean-system:
    #!/usr/bin/env bash
    # prune dangling images, unused flatpaks, old package cache (asks first)
    set -euo pipefail
    . "$HOME/.local/share/ucli/scripts/lib/ui.sh"
    have() { command -v "$1" >/dev/null 2>&1; }

    if have podman; then
    ui_rule "podman: dangling images"
    podman image ls --filter dangling=true || true
    ui_rule "podman: anonymous volumes not in use"
    podman volume ls --filter dangling=true || true
    fi
    if have docker; then
    ui_rule "docker: dangling images"
    docker image ls --filter dangling=true || true
    ui_rule "docker: anonymous volumes not in use"
    docker volume ls --filter dangling=true || true
    fi
    if have flatpak; then
    ui_rule "flatpak: unused runtimes"
    flatpak uninstall --unused --dry-run || true
    fi
    if have pacman; then
    ui_rule "pacman: cache size"
    du -sh /var/cache/pacman/pkg 2>/dev/null || true
    fi

    printf '\nNamed volumes (dev_pgdata, dev_mysql, dev_redis) are never pruned.\n'

    if ui_confirm "Prune the dangling / unused items listed above?"; then
    if have podman; then
    podman image prune -f
    podman volume ls -qf dangling=true | xargs -r podman volume rm
    fi
    if have docker; then
    docker image prune -f
    docker volume ls -qf dangling=true | xargs -r docker volume rm
    fi
    have flatpak && flatpak uninstall --unused -y
    have pacman && sudo pacman -Sc --noconfirm
    ui_rule "done"
    else
    printf '\nNothing removed.\n'
    fi

# Collect machine + toolchain facts into a file you can paste into an issue.
[group('Maintenance')]
report:
    #!/usr/bin/env bash
    set -euo pipefail
    out="${1:-$HOME/report-$(date +%Y%m%d-%H%M).txt}"
    have() { command -v "$1" >/dev/null 2>&1; }
    {
    printf '### system\n'
    uname -a
    ( . /etc/os-release && printf '%s %s\n' "$NAME" "$VERSION" ) 2>/dev/null || true
    printf 'cpu: %s\n' "$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ //')"
    have lspci && lspci -nn | grep -Ei 'vga|3d|display' || true
    printf '\n### desktop\n'
    printf 'session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-?}" "${XDG_SESSION_TYPE:-?}"
    have gnome-shell && gnome-shell --version
    printf '\n### packages\n'
    have pacman && printf 'installed: %s\n' "$(pacman -Q | wc -l)"
    have pacman && printf 'foreign (AUR): %s\n' "$(pacman -Qm | wc -l)"
    have flatpak && flatpak list --columns=application,version 2>/dev/null | awk 'NR<=40'
    printf '\n### toolchain (host)\n'
    for c in just chezmoi docker podman distrobox node npm php composer; do
    printf '%-10s %s\n' "$c" "$(command -v "$c" >/dev/null 2>&1 && { "$c" --version 2>/dev/null | awk 'NR==1'; } || echo MISSING)"
    done
    printf '\n### dev box\n'
    if have distrobox && distrobox list --no-color 2>/dev/null | grep -qE '\bdev\b'; then
    distrobox enter dev -- bash -lc 'printf "debian %s\nnode %s\nphp %s\n" "$(cat /etc/debian_version)" "$(node -v 2>/dev/null || echo MISSING)" "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"' 2>/dev/null || printf 'box present but unreachable\n'
    else
    printf 'no dev box\n'
    fi
    printf '\n### chezmoi / ucli\n'
    printf 'repo: %s\n' "$(git -C "$HOME/.local/share/chezmoi" log --oneline -1 2>/dev/null || echo 'not a git repo')"
    printf 'deployed: %s path(s) out of sync\n' "$(chezmoi status 2>/dev/null | wc -l | tr -d ' ')"
    printf '\n### recent errors\n'
    have journalctl && journalctl -p 3 -b --no-pager 2>/dev/null | tail -20
    } >"$out" 2>&1
    printf 'wrote %s (%s lines)\n' "$out" "$(wc -l <"$out")"
    printf 'no env, no keys, no tokens collected\n'

# Show system logs. Use `ucli --choose` to pick a log source interactively.
[group('Maintenance')]
logs:
    # show journal from this boot
    journalctl --no-hostname -b 0

# Reboot into the firmware settings (dual boot, boot order, secure boot).
[group('Maintenance')]
bios:
    #!/usr/bin/env bash
    # reboot into BIOS/UEFI firmware settings
    set -euo pipefail
    [ -d /sys/firmware/efi ] || { printf 'legacy BIOS: reboot and press the firmware key\n' >&2; exit 1; }
    systemctl reboot --firmware-setup

# Show firmware/board details.
[group('Maintenance')]
bios-info:
    #!/usr/bin/env bash
    # show motherboard/BIOS firmware details
    set -euo pipefail
    # /sys/class/dmi/id is world-readable, so this needs neither dmidecode nor
    # sudo. dmidecode is only a fallback for kernels without dmi-id.
    dmi=/sys/class/dmi/id
    if [ -d "$dmi" ]; then
    for pair in 'sys_vendor|Manufacturer' 'product_name|Product Name' \
    'product_version|Version' 'board_name|Board' \
    'bios_vendor|BIOS Vendor' 'bios_version|BIOS Version' \
    'bios_date|BIOS Date'; do
    key="${pair%%|*}"; label="${pair#*|}"
    [ -r "$dmi/$key" ] || continue
    printf '%-13s %s\n' "$label" "$(cat "$dmi/$key")"
    done
    exit 0
    fi
    if command -v dmidecode >/dev/null 2>&1; then
    sudo dmidecode -t bios -t baseboard \
    | grep -E '^[[:space:]]+(Manufacturer|Product Name|Version|Release Date|Vendor):' \
    | sed 's/^[[:space:]]*//'
    exit 0
    fi
    printf 'no /sys/class/dmi/id and dmidecode is not installed\n' >&2
    exit 1

# Handy when a step "did not run": the gate tells you why.
# What no longer matches its package: unmerged .pacnew/.pacsave files and files
# edited since install (pacman -Qkk). Read-only — the Arch answer to Bluefin's
# `ujust check-local-overrides`.
# Show unmerged .pacnew files and locally modified package files.
[group('Maintenance')]
config-audit *ARGS:
    @~/.local/share/ucli/scripts/check/config-audit.sh {{ARGS}}

# Show ucli state: versioned setup gates (lib/version-script.sh) and the devmode marker.
[group('Maintenance')]
state:
    #!/usr/bin/env bash
    # versioned setup gates + devmode marker
    set -euo pipefail
    . "$HOME/.config/ucli/scripts/lib/version-script.sh"
    statedir="${XDG_STATE_HOME:-$HOME/.local/state}/ucli"
    printf 'state dir: %s\n\n' "$statedir"

    printf 'version gates:\n'
    gates="$(vs_list)"
    if [ -n "$gates" ]; then
    printf '%s\n' "$gates" | awk -F'\t' '{ printf "  %-8s %-26s %s\n", $1, $2, $3 }'
    else
    printf '  (none)\n'
    fi

    printf '\ndevmode:\n'
    if [ -r "$statedir/devmode" ]; then
    sed 's/^/  /' "$statedir/devmode"
    else
    printf '  not configured (ucli devmode sets it up)\n'
    fi

# Packages changed in the most recent pacman transaction.
[group('Maintenance')]
changelogs:
    #!/usr/bin/env bash
    # show packages changed in the last pacman transaction
    set -euo pipefail
    log=/var/log/pacman.log
    [ -r "$log" ] || { printf '%s not readable\n' "$log" >&2; exit 1; }
    awk '
    /\[PACMAN\] Running .pacman -S/ { n++ }
    n == 1 && \[ALPM\] (upgraded|installed|removed) / { print }
    n > 1 { exit }
    ' "$log" | sed 's/^\[\([^]]*\)\] \[ALPM\] /\1 /' | tail -n 40
