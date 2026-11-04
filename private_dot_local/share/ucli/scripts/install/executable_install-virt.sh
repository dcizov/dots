#!/usr/bin/env bash
# Virtual machines: qemu + libvirt + virt-manager on KVM.
#
# Deliberately NOT part of `ucli devmode` (a dev box is a distrobox container;
# a VM is for testing installers, other operating systems and snapshots you
# would not run on the host), and deliberately not a second install path: the
# packages come from the VIRT array in packages.bash via `install-packages.sh
# virt`, exactly like every other tier.
#
# What this adds on top of the packages:
#   * /dev/kvm check — without VT-x/AMD-V enabled in firmware, qemu still works
#     but emulates the CPU and is unusably slow
#   * your user in the `libvirt` group (virt-manager needs it for qemu:///system)
#   * libvirtd enabled (socket-activated; the modular daemons need nothing extra)
#   * libvirt's default NAT network started and set to autostart, so guests get
#     an address and can reach the network
#
# Usage: install-virt.sh [--no-service] [--status] [--yes]
set -euo pipefail

real_user="${SUDO_USER:-$USER}"

mode=apply
take_service=1
yes_flag=0
for arg in "$@"; do
  case "$arg" in
    --status) mode=status ;;
    --no-service) take_service=0 ;;
    --yes|-y) yes_flag=1 ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

has() { command -v "$1" >/dev/null 2>&1; }

# libvirt 9+ ships both the monolithic libvirtd and per-driver modular daemons.
# Enabling the socket starts the daemon on first `virsh`/virt-manager use; the
# plain service is the fallback on a libvirt that predates socket activation.
libvirt_unit() {
  if systemctl cat libvirtd.socket >/dev/null 2>&1; then
    printf 'libvirtd.socket'
  else
    printf 'libvirtd.service'
  fi
}

in_group() { id -nG "$real_user" 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }

kvm_state() {
  if [[ ! -e /dev/kvm ]]; then
    echo "no /dev/kvm — VT-x/AMD-V is off in firmware (or kvm module not loaded)"
  elif [[ -r /dev/kvm && -w /dev/kvm ]]; then
    echo "yes (/dev/kvm usable)"
  else
    echo "yes, but not usable by $real_user (kvm group membership)"
  fi
}

net_state() {
  if ! has virsh; then echo "virsh not installed"; return 0; fi
  if as_root virsh -c qemu:///system net-info default 2>/dev/null | grep -q 'Active:.*yes'; then
    echo "default network: active"
  else
    echo "default network: not started"
  fi
}

if [[ "$mode" == status ]]; then
  printf 'qemu        : %s\n' "$(has qemu-system-x86_64 && echo installed || echo MISSING)"
  printf 'libvirt     : %s\n' "$(has virsh && echo installed || echo MISSING)"
  printf 'virt-manager: %s\n' "$(has virt-manager && echo installed || echo MISSING)"
  printf 'kvm         : %s\n' "$(kvm_state)"
  printf 'libvirt grp : %s\n' "$(in_group libvirt && echo "yes ($real_user)" || echo "no — run 'ucli virt'")"
  if has virsh; then
    unit="$(libvirt_unit)"
    printf 'daemon      : %s %s\n' "$unit" \
      "$(systemctl is-active "$unit" >/dev/null 2>&1 && echo active || echo inactive)"
    printf '%s\n' "$(net_state)"
  fi
  exit 0
fi

# 1. packages: qemu-desktop, libvirt, virt-manager, virt-viewer, edk2-ovmf
#    (UEFI guests), swtpm (emulated TPM 2.0), dnsmasq (libvirt's NAT).
args=()
(( yes_flag )) && args+=(--yes)
"$script_dir/install-packages.sh" ${args[@]+"${args[@]}"} virt

# 2. KVM. A VM without it boots, but emulated — worth saying once, loudly.
if [[ ! -e /dev/kvm ]]; then
  cat >&2 <<'KVM'
warning: /dev/kvm is missing, so guests will run emulated (slow).
         Enable VT-x / AMD-V (SVM) in firmware, and make sure the CPU supports it:
           lscpu | grep -i virtualization
KVM
fi

# 3. Group membership. `libvirt` is created by the libvirt package, so this can
#    only work after step 1.
if in_group libvirt; then
  echo "libvirt group: $real_user already a member"
else
  echo "adding $real_user to the libvirt group"
  as_root usermod -aG libvirt "$real_user"
  echo "  note: group membership applies to new sessions — log out and back in"
fi

# 4. The daemon.
if (( take_service )); then
  unit="$(libvirt_unit)"
  echo "enabling $unit"
  as_root systemctl enable --now "$unit"
else
  echo "skipping the libvirtd unit (--no-service); start it with:" >&2
  echo "  sudo systemctl enable --now $(libvirt_unit)" >&2
fi

# 5. libvirt's default NAT network (192.168.122.0/24) — guests get DHCP from it.
#    Non-fatal: on a first run the daemon may still be starting.
if (( take_service )) && has virsh; then
  as_root virsh -c qemu:///system net-start default >/dev/null 2>&1 || true
  as_root virsh -c qemu:///system net-autostart default >/dev/null 2>&1 || true
  echo "$(net_state)"
fi

cat <<'NEXT'

==> virtual machines are ready

    ucli virt --status      # packages, /dev/kvm, group, daemon, default network
    virt-manager            # the GUI (or: virt-install for the CLI)

    Notes:
      - guests use qemu:///system; that is why the libvirt group matters
      - nested virtualisation, GPU passthrough and bridge networking are host
        decisions this script does not make for you
      - a container (`ucli devbox`) is the cheaper answer for "just a Debian"
NEXT
