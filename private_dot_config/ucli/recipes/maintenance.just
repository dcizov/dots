# Day-to-day maintenance, mirroring the useful half of Bluefin's ujust:
#
#   ujust update          -> ucli update
#   ujust clean-system    -> ucli clean-system   (dangling containers only)
#   ujust device-info     -> ucli report         (written to a file, no pastebin)
#   ujust logs-this-boot  -> ucli logs           (menu: this/last boot, devbox)
#   ujust bios, bios-info -> ucli bios, ucli bios-info
#   ujust changelogs      -> ucli changelogs     (from /var/log/pacman.log)
#
# Deliberately NOT ported: toggle-updates / rebase-helper / powerwash (bootc
# image concepts), enroll-secure-boot-key (ublue/Nvidia specific), benchmark and
# check-idle-power-draw (need stress-ng/powerstat), toggle-iwd / toggle-tpm2
# (rewrite the network and disk stack; do those by hand).

# Update everything: pacman, AUR, flatpaks, mise runtimes, then the dev box.
[group('Maintenance')]
update:
    # full system upgrade: pacman + AUR + flatpaks + mise + dev box
    #!/usr/bin/env bash
    set -euo pipefail
    step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
    have() { command -v "$1" >/dev/null 2>&1; }

    step "pacman: system upgrade"
    sudo pacman -Syu --noconfirm

    if have paru; then
      step "paru: AUR upgrades"
      paru -Sua --noconfirm || printf 'paru: nothing to do, or it failed\n' >&2
    elif have yay; then
      step "yay: AUR upgrades"
      yay -Sua --noconfirm || printf 'yay: nothing to do, or it failed\n' >&2
    fi

    if have flatpak; then
      step "flatpak: updates"
      flatpak update -y
    fi

    if have mise; then
      step "mise: runtimes"
      mise upgrade || true
    fi

    step "dev box"
    "$HOME/.config/ucli/scripts/devbox/executable_devbox-reconcile.sh"

    step "done"
    printf 'A reboot is only needed for kernel/driver updates.\n'

# Named volumes are NEVER touched — dev_pgdata / dev_mysql hold your databases.
# Reclaim space: dangling images, unused flatpaks, old package cache.
[group('Maintenance')]
clean-system:
    # prune dangling images, unused flatpaks, old package cache (asks first)
    #!/usr/bin/env bash
    set -euo pipefail
    . "$HOME/.config/ucli/scripts/lib/choose.sh"
    have() { command -v "$1" >/dev/null 2>&1; }
    step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

    if have podman; then
      step "podman: dangling images"
      podman image ls --filter dangling=true || true
      step "podman: anonymous volumes not in use"
      podman volume ls --filter dangling=true || true
    fi
    if have docker; then
      step "docker: dangling images"
      docker image ls --filter dangling=true || true
      step "docker: anonymous volumes not in use"
      docker volume ls --filter dangling=true || true
    fi
    if have flatpak; then
      step "flatpak: unused runtimes"
      flatpak uninstall --unused --dry-run || true
    fi
    if have pacman; then
      step "pacman: cache size"
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
      step "done"
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

# System logs: menu over this boot, last boot and the devbox provisioning log.
[group('Maintenance')]
logs:
    # view system logs: this boot / last boot / devbox / pacman
    #!/usr/bin/env bash
    set -euo pipefail
    . "$HOME/.config/ucli/scripts/lib/choose.sh"
    have() { command -v "$1" >/dev/null 2>&1; }
    have journalctl || { printf 'journalctl not found\n' >&2; exit 1; }
    what="$(ui_choose 'logs' \
      'this-boot|all messages from the current boot' \
      'last-boot|all messages from the previous boot' \
      'devbox|/var/log/devbox-provision.log inside the dev box' \
      'pacman|recent package transactions')" || exit 0
    case "$what" in
      this-boot) show journalctl -b --no-pager ;;
      last-boot) show journalctl -b -1 --no-pager ;;
      devbox)    distrobox enter dev -- sudo tail -n 200 /var/log/devbox-provision.log ;;
      pacman)
        [ -r /var/log/pacman.log ] || { printf 'no /var/log/pacman.log on this machine\n' >&2; exit 1; }
        show grep -E '^\[.*\] \[ALPM\] (upgraded|installed|removed) ' /var/log/pacman.log
        ;;
    esac

# Reboot into the firmware settings (dual boot, boot order, secure boot).
[group('Maintenance')]
bios:
    # reboot into BIOS/UEFI firmware settings
    #!/usr/bin/env bash
    set -euo pipefail
    . "$HOME/.config/ucli/scripts/lib/choose.sh"
    [ -d /sys/firmware/efi ] || { printf 'legacy BIOS: reboot and press the firmware key\n' >&2; exit 1; }
    if ui_confirm "Reboot into the BIOS/UEFI settings now?"; then
      systemctl reboot --firmware-setup
    fi

# Show firmware/board details.
[group('Maintenance')]
bios-info:
    # show motherboard/BIOS firmware details
    #!/usr/bin/env bash
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

# Packages changed in the most recent pacman transaction.
[group('Maintenance')]
changelogs:
    # show packages changed in the last pacman transaction
    #!/usr/bin/env bash
    set -euo pipefail
    log=/var/log/pacman.log
    [ -r "$log" ] || { printf '%s not readable\n' "$log" >&2; exit 1; }
    awk '
      /\[PACMAN\] Running .pacman -S/ { n++ }
      n == 1 && /\[ALPM\] (upgraded|installed|removed) / { print }
      n > 1 { exit }
    ' "$log" | sed 's/^\[\([^]]*\)\] \[ALPM\] /\1 /' | tail -n 40
