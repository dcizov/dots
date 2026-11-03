#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HOME/.config/ucli/scripts/lib/detect.sh"

printf 'configured.machine: %s\n' "$(ucli_profile_value machine auto)"
printf 'configured.desktop: %s\n' "$(ucli_profile_value desktop auto)"
printf 'configured.terminal: %s\n' "$(ucli_profile_value terminal auto)"
printf 'configured.role: %s\n' "$(ucli_profile_value role dev)"
printf 'configured.gaming: %s\n' "$(ucli_profile_value gaming false)"
# the port lives in devbox.env (plain file, read by provision-dev.sh), not in
# chezmoi data — the hook in dev.ini cannot be templated.
devbox_ssh_port() {
  local port=""
  if [[ -r "$HOME/.config/distrobox/devbox.env" ]]; then
    port="$(sed -n 's/^DEVBOX_SSH_PORT=//p' "$HOME/.config/distrobox/devbox.env" | head -1)"
  fi
  printf '%s' "${port:-2222}"
}
printf 'configured.devbox_ssh_port: %s\n' "$(devbox_ssh_port)"
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
