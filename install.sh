#!/usr/bin/env bash
set -euo pipefail

REPO="${WTFAQ_REPO:-https://github.com/dcizov/dots.git}"
BRANCH="${WTFAQ_BRANCH:-}"
APPLY=1
YES=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
usage: install.sh [--repo URL] [--branch BRANCH] [--no-apply] [--yes] [--dry-run]

Bootstrap wtfaq chezmoi/ucli setup on a console-only machine.

Installs git, chezmoi and just, then deploys the ucli runtime only: ~/.local/bin/ucli,
~/.config/ucli, ~/.local/share/ucli and a ~/.bash_profile that puts ~/.local/bin on
PATH. Everything desktop-shaped — zsh, oh-my-zsh, starship, ~/.config/ghostty,
~/.config/ucli/firefox — is deliberately left to `ucli setup-system`, so a fresh install
stays small enough to snapshot.

  ucli setup-snapshots          # snapper + limine, snapshot #1
  ucli setup-system gnome       # base + desktop + shell + dotfiles + snapshot

WARNING: The recommended install method pipes a remote script directly into bash
  (curl https://install.wtfaq.tech | bash). Verify the script contents before
  piping it, or download and inspect it first.

Examples:
  curl -fsSL https://install.wtfaq.tech | bash
  curl -fsSL https://install.wtfaq.tech | bash -s -- --repo https://github.com/dcizov/dots.git
  curl -fsSL https://install.wtfaq.tech | bash -s -- --branch main
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

detect_distro_like() {
  # shellcheck disable=SC1091
  . /etc/os-release
  printf '%s\n' "${ID_LIKE:-}"
}

ensure_local_bin() {
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
}

install_arch_requirements() {
  # Only what this script and chezmoi itself need. zsh is NOT here: it belongs to
  # the shell tier (`install-packages.sh shell-tools`) which runs with the desktop
  # step, so a console-only box does not carry a shell it will never log into.
  local packages=(
    ca-certificates
    curl
    git
    chezmoi
    just
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
  local distro like
  distro="$(detect_distro)"
  like="$(detect_distro_like)"

  case "$distro" in
    arch|archlinux|cachyos)
      install_arch_requirements
      ;;
    *)
      # EndeavourOS, Garuda, Arco, Artix, Manjaro… share /etc/os-release,
      # /etc/pacman.conf and the package names used here. Refuse only what is not
      # Arch under the hood.
      if [[ " ${like} " == *" arch "* ]]; then
        warn "'$distro' is Arch-based (ID_LIKE=$like); continuing with Arch paths and pacman"
        warn "  CachyOS-specific handling (chwd for GPU, its own repos) will not apply"
        install_arch_requirements
      else
        die "unsupported distro: $distro (ID_LIKE=${like:-none}). Supports Arch, CachyOS and Arch derivatives."
      fi
      ;;
  esac
}

run_chezmoi_init() {
  local args=(init)

  [[ -n "$BRANCH" ]] && args+=(--branch "$BRANCH")
  args+=("$REPO")

  if (( DRY_RUN )); then
    log "[dry-run] would run: chezmoi ${args[*]}"
    log "[dry-run] would run: chezmoi apply -v ${CONSOLE_TARGETS[*]}"
    return 0
  fi

  log "Running: chezmoi ${args[*]}"
  chezmoi "${args[@]}"

  (( APPLY )) || return 0
  apply_console_dotfiles
}

# The console epoch: ucli itself, its recipes/scripts, and a PATH. That is the
# whole point of stopping here — `chezmoi apply` with no arguments on a TTY-only
# box would also deploy ~/.config/atuin, bat, eza, distrobox, … for programs that
# are not installed; the guard for that is .chezmoiignore, and the minimal
# request is this target list.
CONSOLE_TARGETS=(
  "$HOME/.local/bin/ucli"
  "$HOME/.config/ucli"
  "$HOME/.local/share/ucli"
  "$HOME/.bash_profile"
)

apply_console_dotfiles() {
  log "Deploying the ucli runtime (the desktop step brings the rest)"
  chezmoi apply -v "${CONSOLE_TARGETS[@]}" \
    || warn "chezmoi apply failed; run 'ucli chezmoi-apply' once ucli is on PATH"
}

print_next_steps() {
  cat <<'EOF'

Done. This machine now has ucli, and ~/.local/bin on PATH from ~/.bash_profile.

No shell tier, no terminal config, no browser config yet: those arrive with the
desktop, because ~/.zshrc, ~/.config/zsh, starship.toml, ~/.config/ghostty and
~/.config/ucli/firefox are only deployed once the programs exist (.chezmoiignore asks
lookPath on every apply). That keeps the fresh-install snapshot small.

Next, in this order:

  ucli setup-snapshots        # snapper + limine + snapshot #1 (btrfs)
  ucli setup-system gnome     # base packages, DE, terminal, firefox, shell,
                              # GNOME extensions, then the dotfiles, then a snapshot
  ucli doctor                 # what is still missing

Then log out and back in: zsh becomes your login shell and GNOME extensions load.

Optional later:

  ucli cli                    # shell cosmetics (eza, bat, zoxide, atuin, …)
  ucli apps                   # personal apps, flatpaks, Firefox config
  ucli devmode                # dev tools + dev box
  ucli gaming

Browse commands:

  ucli --choose

Direct tools remain direct:

  chezmoi diff && chezmoi apply -v
  distrobox assemble create --file ~/.config/distrobox/dev.ini

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