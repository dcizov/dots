#!/usr/bin/env bash
set -euo pipefail

REPO="${WTFAQ_REPO:-https://github.com/wtfaq/dotfiles.git}"
BRANCH="${WTFAQ_BRANCH:-}"
APPLY=1
YES=0

usage() {
  cat <<'USAGE'
usage: install.sh [--repo URL] [--branch BRANCH] [--no-apply] [--yes]

Bootstrap wtfaq chezmoi/ucli setup.

Examples:
  curl -fsSL https://install.wtfaq.tech | bash
  curl -fsSL https://install.wtfaq.tech | bash -s -- --repo https://github.com/wtfaq/dotfiles.git
  curl -fsSL https://install.wtfaq.tech | bash -s -- --branch master
USAGE
}

while (($#)); do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --repo=*)
      REPO="${1#*=}"
      shift
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --branch=*)
      BRANCH="${1#*=}"
      shift
      ;;
    --no-apply)
      APPLY=0
      shift
      ;;
    --yes|-y)
      YES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  (( YES )) && return 0
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" == y || "$ans" == Y || "$ans" == yes ]]
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die "Linux required"
}

detect_distro() {
  # shellcheck disable=SC1091
  . /etc/os-release
  printf '%s\n' "${ID:-unknown}"
}

ensure_local_bin() {
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
}

install_arch_requirements() {
  local packages=(
    ca-certificates
    curl
    git
    chezmoi
    just
    zsh
    openssh
    nano
  )

  log "Installing bootstrap packages with pacman"
  sudo pacman -Syu --needed "${packages[@]}"
}

install_requirements() {
  local distro
  distro="$(detect_distro)"

  case "$distro" in
    arch|cachyos)
      install_arch_requirements
      ;;
    *)
      die "unsupported distro: $distro. This bootstrap currently supports Arch/CachyOS only."
      ;;
  esac
}

run_chezmoi_init() {
  local args=(init)

  [[ -n "$BRANCH" ]] && args+=(--branch "$BRANCH")
  (( APPLY )) && args+=(--apply)

  args+=("$REPO")

  log "Running: chezmoi ${args[*]}"
  chezmoi "${args[@]}"
}

print_next_steps() {
  cat <<'EOF'

Done.

Next recommended flow:

  ucli profile
  ucli doctor
  ucli validate

  ucli setup-snapshots
  ucli setup-system

Optional later:

  ucli cli
  ucli devmode
  ucli apps
  ucli gaming

Browse commands:

  ucli --choose

Direct tools remain direct:

  chezmoi diff && chezmoi apply -v
  distrobox assemble create --file ~/.config/distrobox/dev.ini
  cd ~/.config/dev-services && docker compose up -d

EOF
}

main() {
  require_linux
  ensure_local_bin

  log "Repository: $REPO"
  [[ -n "$BRANCH" ]] && log "Branch: $BRANCH"

  if (( ! YES )); then
    confirm "Bootstrap wtfaq dotfiles on this machine?" || exit 0
  fi

  install_requirements
  run_chezmoi_init

  if ! command -v ucli >/dev/null 2>&1; then
    warn "ucli is not on PATH yet. Try opening a new shell or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  print_next_steps
}

main "$@"