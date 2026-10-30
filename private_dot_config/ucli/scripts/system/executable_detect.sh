#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../lib/detect.sh"

printf 'configured.machine: %s\n' "$(ucli_profile_value machine auto)"
printf 'configured.desktop: %s\n' "$(ucli_profile_value desktop auto)"
printf 'configured.terminal: %s\n' "$(ucli_profile_value terminal auto)"
printf 'configured.role: %s\n' "$(ucli_profile_value role dev)"
printf 'configured.gaming: %s\n' "$(ucli_profile_value gaming false)"
printf 'configured.devbox_ssh_port: %s\n' "$(ucli_profile_value devbox_ssh_port 2222)"
echo
printf 'detected.distro: %s\n' "$(detect_distro)"
printf 'detected.arch: %s\n' "$(detect_arch)"
printf 'detected.cpu: %s\n' "$(detect_cpu)"
printf 'detected.gpu: %s\n' "$(detect_gpu)"
printf 'detected.machine: %s\n' "$(detect_machine)"
printf 'detected.virtualization: %s\n' "$(detect_virtualization)"
printf 'detected.desktop_session: %s\n' "$(detect_desktop_session)"
printf 'detected.installed_desktop: %s\n' "$(detect_installed_desktop || true)"
printf 'detected.desktop: %s\n' "$(detect_desktop || true)"
printf 'detected.terminal: %s\n' "$(detect_terminal)"
echo
printf 'root.fstype: %s\n' "$(detect_root_fstype)"
printf 'root.source: %s\n' "$(detect_root_source)"
printf 'root.options: %s\n' "$(detect_root_options)"
printf 'btrfs.layout: %s\n' "$(detect_btrfs_layout || true)"
printf 'snapper.root: %s\n' "$(detect_snapper_root || true)"
printf 'limine: %s\n' "$(detect_limine || true)"
