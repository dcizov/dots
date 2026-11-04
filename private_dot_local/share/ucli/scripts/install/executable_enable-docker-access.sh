#!/usr/bin/env bash
# Make `docker` usable by the person who runs it — installing the package is not
# enough, because on Arch the daemon is disabled and nobody is in the docker
# group, so every `docker` command either fails or needs sudo.
#
#   systemctl enable --now docker.service    without it: "Cannot connect to the
#                                            Docker daemon"
#   usermod -aG docker <user>                without it: permission denied on
#                                            /var/run/docker.sock
#
# podman is deliberately NOT touched: in this repo it exists as distrobox's
# backend, which is rootless and needs neither a socket nor a group. Docker is
# the dev runtime (compose files, devcontainers, project Dockerfiles).
#
# Bluefin's equivalent is `ujust dx-group`, which also covers libvirt/dialout;
# this repo only ships docker, so only docker is granted.
#
# Idempotent: prints what it changed and what was already fine.
#
# Usage: enable-docker-access.sh [--no-service] [--status]
set -euo pipefail

real_user="${SUDO_USER:-$USER}"

take_service=1
mode=apply
for arg in "$@"; do
  case "$arg" in
    --no-service) take_service=0 ;;
    --status) mode=status ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed; nothing to grant (run: ucli devmode)"
  exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../lib/common.sh"

in_docker_group() { id -nG "$real_user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; }
service_enabled() { systemctl is-enabled docker.service >/dev/null 2>&1; }
service_running() { systemctl is-active --quiet docker.service; }

if [[ "$mode" == status ]]; then
  printf 'docker.service : %s / %s\n' \
    "$(service_enabled && echo enabled || echo disabled)" \
    "$(service_running && echo running || echo stopped)"
  printf 'docker group   : %s\n' "$(in_docker_group && echo "$real_user is a member" || echo "$real_user is NOT a member")"
  exit 0
fi

if (( take_service )); then
  if service_enabled && service_running; then
    echo "docker.service: already enabled and running"
  else
    echo "docker.service: enabling and starting"
    as_root systemctl enable --now docker.service
  fi
fi

if in_docker_group; then
  echo "docker group: $real_user is already a member"
else
  echo "docker group: adding $real_user"
  as_root usermod -aG docker "$real_user"
  echo
  echo "  NOTE: group membership only applies to new sessions."
  echo "        Log out and back in (or run: newgrp docker) before using docker"
  echo "        without sudo."
fi

echo
echo "Verify with: docker info"
