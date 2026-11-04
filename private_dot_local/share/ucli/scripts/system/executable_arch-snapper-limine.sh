#!/usr/bin/env bash
set -euo pipefail

yes_flag=0
dry_run=0
force=0
take_snapshot=1
remove_home_snapshots=1
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --dry-run|-n) dry_run=1 ;;
    --keep-home-snapshots) remove_home_snapshots=0 ;;
    --force) force=1 ;;
    --no-snapshot) take_snapshot=0 ;;
    --help|-h)
      cat <<'USAGE'
usage: sudo arch-snapper-limine.sh [--yes] [--dry-run] [--force] [--no-snapshot] [--keep-home-snapshots]

Arch family post-install system setup (Arch, CachyOS, EndeavourOS, …):
- verifies Btrfs subvolume layout @, @home, @log, @pkg
- removes archinstall-created @home/.snapshots by default
- configures root Snapper with CachyOS-style root config
- installs/enables snapper cleanup, snap-pac, limine-snapper-sync
- configures mkinitcpio systemd hooks plus sd-btrfs-overlayfs
- configures /etc/default/limine preserving current kernel cmdline base
- runs mkinitcpio -P, limine-update, limine-snapper-sync
- creates the fresh-installation snapshot (skipped with --no-snapshot)

CachyOS ships this whole stack itself (snapper root config, snap-pac,
limine-snapper-sync, the mkinitcpio hooks, /etc/default/limine), so there the
script explains what it left alone and exits. --force runs the Arch path anyway.
USAGE
      exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

run() {
  printf '+ %q ' "$@"; echo
  if (( ! dry_run )); then "$@"; fi
}

write_file() {
  local path="$1"
  shift
  echo "+ write $path"
  if (( ! dry_run )); then
    install -Dm644 /dev/stdin "$path"
  else
    cat >/dev/null
  fi
}

backup() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  local bak
  bak="${path}.bak.$(date +%F-%H%M%S)"
  run cp -a "$path" "$bak"
}

confirm() {
  local msg="$1"
  (( yes_flag )) && return 0
  read -r -p "$msg [y/N] " ans
  [[ "$ans" == y || "$ans" == Y || "$ans" == yes ]]
}

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

. /etc/os-release

# Arch family. Everything below (pacman, /etc/snapper, mkinitcpio, limine) comes
# from Arch, so CachyOS, EndeavourOS, Garuda and friends take the same path; only
# non-Arch systems are refused outright.
case "${ID:-}" in
  arch|archlinux|cachyos) ;;
  *)
    if [[ " ${ID_LIKE:-} " == *" arch "* ]]; then
      echo "note: ID=$ID is Arch-based (ID_LIKE=$ID_LIKE); continuing with Arch paths" >&2
    else
      echo "unsupported: ID=${ID:-unknown} is not Arch-based; nothing here applies" >&2
      exit 1
    fi
    ;;
esac

# CachyOS already ships the whole stack: snapper's root config, snap-pac,
# limine-snapper-sync and limine-mkinitcpio-hook in its own repositories, and
# Calamares writes /etc/default/limine. Rewriting that is how you break a boot.
if [[ "${ID:-}" == "cachyos" ]] && (( ! force )); then
  cat <<'EOF'
CachyOS detected: the Snapper + Limine stack is installer-owned there, so nothing
was changed. Already in place on a CachyOS install:

  /etc/snapper/configs/root     snapper root config
  snap-pac                      one snapshot per pacman transaction
  limine-snapper-sync           snapshot -> boot entry sync
  limine-mkinitcpio-hook        initramfs per snapshot
  /etc/default/limine           kernel command line

To take a restore point right now:

  sudo snapshot-fresh-install.sh "Fresh CachyOS Installation"

To run the Arch path anyway (backs up and overwrites those files):

  sudo arch-snapper-limine.sh --force
EOF
  exit 0
fi

if [[ "$(findmnt -no FSTYPE /)" != btrfs ]]; then
  echo "Root filesystem is not btrfs; refusing." >&2
  exit 1
fi

subvols="$(btrfs subvolume list /)"
for required in '@' '@home' '@log' '@pkg'; do
  if ! grep -Eq " path ${required}$" <<<"$subvols"; then
    echo "Required Btrfs subvolume missing: $required" >&2
    echo "$subvols" >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Install packages: pacman part first, then AUR helper part as the invoking sudo user.
if (( yes_flag )); then
  run pacman -S --needed --noconfirm btrfs-progs snapper snap-pac limine
else
  run pacman -S --needed btrfs-progs snapper snap-pac limine
fi
aur_helper="$("$script_dir/../install/install-aur-helper.sh" "${yes_flag:+--yes}")"
echo "AUR helper: $aur_helper"
if ! command -v "$aur_helper" >/dev/null 2>&1; then
  echo "$aur_helper not available after install attempt" >&2
  exit 1
fi
if [[ "$aur_helper" == "paru" ]]; then
  if (( yes_flag )); then
    run sudo -u "${SUDO_USER:-$USER}" paru -S --needed --noconfirm limine-snapper-sync limine-mkinitcpio-hook
  else
    run sudo -u "${SUDO_USER:-$USER}" paru -S --needed limine-snapper-sync limine-mkinitcpio-hook
  fi
elif [[ "$aur_helper" == "shelly" ]]; then
  run sudo -u "${SUDO_USER:-$USER}" shelly install aur limine-snapper-sync limine-mkinitcpio-hook --needed --no-confirm
fi

# Remove home snapper config/subvolume created by archinstall if requested.
if (( remove_home_snapshots )); then
  if [[ -f /etc/snapper/configs/home ]]; then
    confirm "Delete snapper home config?" && run snapper -c home delete-config || true
  fi

  if grep -Eq ' path @home/.snapshots$' <<<"$subvols"; then
    if confirm "Delete @home/.snapshots subvolume and remove /home/.snapshots fstab entry?"; then
      backup /etc/fstab
      if findmnt /home/.snapshots >/dev/null 2>&1; then
        run umount /home/.snapshots
      fi
      # Remove fstab line for /home/.snapshots.
      if (( ! dry_run )); then
        sed -i '\|[[:space:]]/home/.snapshots[[:space:]]|d' /etc/fstab
      fi
			root_src="$(findmnt -no SOURCE /)"
			root_src="${root_src%%[*}"

			tmp="$(mktemp -d)"
			trap 'umount "$tmp" 2>/dev/null || true; rmdir "$tmp" 2>/dev/null || true' EXIT
			run mount -o subvolid=5 "$root_src" "$tmp"
      if [[ -d "$tmp/@home/.snapshots" ]]; then
        run btrfs subvolume delete "$tmp/@home/.snapshots"
      fi
      run umount "$tmp"
      rmdir "$tmp" 2>/dev/null || true
      trap - EXIT
    fi
  fi
fi

# Configure root snapper in CachyOS style.
run mkdir -p /etc/snapper/configs
backup /etc/snapper/configs/root
cat <<'ROOTSNAPPER' | write_file /etc/snapper/configs/root
# subvolume to snapshot
SUBVOLUME="/"

# filesystem type
FSTYPE="btrfs"

# btrfs qgroup for space aware cleanup algorithms
QGROUP=""

# fraction or absolute size of the filesystems space the snapshots may use
SPACE_LIMIT="0.5"

# fraction or absolute size of the filesystems space that should be free
FREE_LIMIT="0.2"

# users and groups allowed to work with config
ALLOW_USERS=""
ALLOW_GROUPS=""

# sync users and groups from ALLOW_USERS and ALLOW_GROUPS to .snapshots directory
SYNC_ACL="no"

# start comparing pre- and post-snapshot in background after creating post-snapshot
BACKGROUND_COMPARISON="yes"

# run daily number cleanup
NUMBER_CLEANUP="yes"

# limit for number cleanup
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="15"

# create hourly snapshots
TIMELINE_CREATE="no"

# cleanup hourly snapshots after some time
TIMELINE_CLEANUP="yes"

# limits for timeline cleanup
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"

# cleanup empty pre-post-pairs
EMPTY_PRE_POST_CLEANUP="yes"

# limits for empty pre-post-pair cleanup
EMPTY_PRE_POST_MIN_AGE="1800"
ROOTSNAPPER

# /.snapshots must be a Btrfs subvolume (not a plain directory)
# mkdir -p creates a regular directory which limine-snapper-sync rejects.
# Per Arch Wiki snapper setup, create the subvolume properly.
if [[ -e /.snapshots ]] && ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  # It's a regular directory (e.g. leftover from mkdir -p); remove it
  run rm -rf /.snapshots
fi
if ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  run btrfs subvolume create /.snapshots
  run chmod 750 /.snapshots
fi

backup /etc/conf.d/snapper
if [[ -f /etc/conf.d/snapper ]]; then
  if (( ! dry_run )); then
    if grep -q '^SNAPPER_CONFIGS=' /etc/conf.d/snapper; then
      sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root"/' /etc/conf.d/snapper
    else
      echo 'SNAPPER_CONFIGS="root"' >> /etc/conf.d/snapper
    fi
  fi
else
  echo 'SNAPPER_CONFIGS="root"' | write_file /etc/conf.d/snapper
fi

run systemctl enable --now snapper-cleanup.timer
# Timeline creation is disabled in config; enabling timer is unnecessary.
run systemctl disable --now snapper-timeline.timer || true

# mkinitcpio: systemd hooks based on CachyOS Calamares initcpiocfg, plus sd-btrfs-overlayfs per ArchWiki Limine page.
backup /etc/mkinitcpio.conf
if (( ! dry_run )); then
  python - <<'PY'
from pathlib import Path
p = Path('/etc/mkinitcpio.conf')
s = p.read_text()
old_hooks = []
for line in s.splitlines():
    if line.strip().startswith('HOOKS='):
        inner = line.split('=',1)[1].strip().strip('()')
        old_hooks = inner.split()
        break
hooks = ['base','systemd','autodetect','microcode','kms','modconf','block','keyboard','sd-vconsole']
if 'plymouth' in old_hooks or Path('/usr/lib/initcpio/hooks/plymouth').exists():
    hooks.append('plymouth')
if 'sd-encrypt' in old_hooks or 'encrypt' in old_hooks:
    hooks.append('sd-encrypt')
if 'lvm2' in old_hooks:
    hooks.append('lvm2')
if 'resume' in old_hooks:
    hooks.append('resume')
hooks += ['filesystems','sd-btrfs-overlayfs']
# Preserve uncommon hooks not intentionally replaced.
replaced = {'udev','keymap','consolefont','encrypt','btrfs-overlayfs'}
for h in old_hooks:
    if h not in hooks and h not in replaced:
        hooks.append(h)
new_line = 'HOOKS=(' + ' '.join(hooks) + ')'
lines=[]
changed=False
for line in s.splitlines():
    if line.strip().startswith('HOOKS='):
        lines.append(new_line)
        changed=True
    else:
        lines.append(line)
if not changed:
    lines.append(new_line)
p.write_text('\n'.join(lines) + '\n')
PY
fi

# /etc/default/limine. Follow ArchWiki recommendation: use /proc/cmdline as source, not from ISO/snapshot.
backup /etc/default/limine
current_cmdline="$(cat /proc/cmdline)"
# Strip transient/noisy options and normalize rootflags.
base_cmdline=""
for tok in $current_cmdline; do
  case "$tok" in
    BOOT_IMAGE=*|initrd=*|quiet|splash|loglevel=*|audit=*|nowatchdog|rootflags=*) ;;
    rw|ro) ;;
    *) base_cmdline+=" $tok" ;;
  esac
done
base_cmdline="${base_cmdline# }"
# Ensure expected root subvolume and btrfs flags.
base_cmdline="$base_cmdline zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs"
cat > /tmp/ucli-limine-default <<EOF2
KERNEL_CMDLINE[default]="$base_cmdline"
KERNEL_CMDLINE[default]+=" quiet loglevel=3 audit=0 nowatchdog splash"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOF2
cat /tmp/ucli-limine-default | write_file /etc/default/limine
rm -f /tmp/ucli-limine-default

run mkinitcpio -P
if command -v limine-update >/dev/null 2>&1; then
  run limine-update
else
  echo "limine-update not found; limine-mkinitcpio-hook package may not have installed correctly" >&2
fi

if command -v limine-snapper-sync >/dev/null 2>&1; then
  run limine-snapper-sync
  run systemctl enable --now limine-snapper-sync.service
else
  echo "limine-snapper-sync not found" >&2
fi

# Snapshot #1. One implementation for every restore point in the repo: it also
# carries --no-snapshot / UCLI_NO_SNAPSHOT, so callers forward rather than reimplement.
snapshot_args=()
(( take_snapshot )) || snapshot_args+=(--no-snapshot)
(( dry_run )) && snapshot_args+=(--dry-run)
run "$script_dir/snapshot-fresh-install.sh" "${snapshot_args[@]}" "Fresh Arch Linux Installation"

echo "Arch Snapper/Limine setup complete. Review /etc/default/limine, /etc/mkinitcpio.conf, and limine-snapper-info."
