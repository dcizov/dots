#!/usr/bin/env bash
set -euo pipefail

REPO="${WTFAQ_REPO:-https://github.com/dcizov/dots.git}"
BRANCH="${WTFAQ_BRANCH:-}"
APPLY=0
YES=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
usage: install.sh [--repo URL] [--branch BRANCH] [--apply] [--yes] [--dry-run]

Bootstrap wtfaq chezmoi/ucli setup.

By default, install.sh clones the dotfiles repo to ~/.local/share/chezmoi
(chezmoi init) but does NOT apply. Run `chezmoi apply -v` or `ucli chezmoi-apply`
after re-login to deploy the dotfiles.

WARNING: The recommended install method pipes a remote script directly into bash
  (curl https://install.wtfaq.tech | bash). Verify the script contents before
  piping it, or download and inspect it first.

Examples:
  curl -fsSL https://install.wtfaq.tech | bash
  curl -fsSL https://install.wtfaq.tech | bash -s -- --repo https://github.com/dcizov/dots.git
  curl -fsSL https://install.wtfaq.tech | bash -s -- --branch main
  curl -fsSL https://install.wtfaq.tech | bash -s -- --apply   # init + apply in one step
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
    --apply)
      APPLY=1
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
    --dry-run)
      DRY_RUN=1
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

  if (( DRY_RUN )); then
    log "[dry-run] would run: sudo pacman -S --needed ${packages[*]}"
    return 0
  fi

  log "Installing bootstrap packages with pacman"
  # Install only needed bootstrap packages without a full system upgrade.
  # A full -Syu during bootstrap can pull in unrelated changes and break
  # the system. Update the system separately after bootstrap completes.
  sudo pacman -S --needed "${packages[@]}"
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

  if (( DRY_RUN )); then
    log "[dry-run] would run: chezmoi ${args[*]}"
    return 0
  fi

  log "Running: chezmoi ${args[*]}"
  chezmoi "${args[@]}"
}

print_next_steps() {
  cat <<'EOF'

Done.

The dotfiles repo is now cloned to ~/.local/share/chezmoi (chezmoi init) but
NOT applied. Re-login so your new shell picks up ~/.zshrc and the PATH from
~/.config/zsh/conf.d/00-env.zsh (including $HOME/.local/bin).

Then apply the dotfiles:

  chezmoi apply -v
  # or:
  ucli chezmoi-apply

Next recommended flow (after apply + re-login):

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

  chezmoi diff
  distrobox assemble create --file ~/.config/distrobox/dev.ini
  cd ~/.config/dev-services && docker compose up -d

EOF
}

main() {
  require_linux
  ensure_local_bin

  log "Repository: $REPO"
  [[ -n "$BRANCH" ]] && log "Branch: $BRANCH"

  if (( DRY_RUN )); then
    log "[dry-run] no changes will be made"
  fi

  if (( ! YES )) && (( ! DRY_RUN )); then
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