#!/usr/bin/env bash
set -euo pipefail

# Install/enable GNOME Shell extensions using gnome-extensions-cli (gext).
#
# Usage:
#   install-gnome-extension-set.sh system   # default system extensions (from GNOME_SYSTEM_EXTENSION_PACKAGES)
#   install-gnome-extension-set.sh overrides # app overrides (from GNOME_APP_OVERRIDES + GNOME_SHELL_OVERRIDES)
#
# Package-based extensions (gnome-shell-extensions, etc.) are installed via
# pacman/paru by install-packages.sh. This script handles non-repo extensions
# via gext (gnome-extensions-cli) and enables all extensions.
#
# Enabling is ONE write to org.gnome.shell enabled-extensions instead of N
# `gext enable` calls (ipted from Bluefin, which sets the whole list in its
# gschema override). The existing list is preserved and merged, so extensions
# the user enabled themselves are never dropped.
#
# Source: https://github.com/essembeh/gnome-extensions-cli

usage() {
  cat <<'USAGE'
usage: install-gnome-extension-set.sh [system|overrides] [--force]

  system   Enable repo-packaged default GNOME system extensions
  overrides Install GNOME app override packages and shell override themes
  --force  run even when the gate says this set is unchanged
USAGE
}

mode="system"
force=0
for arg in "$@"; do
  case "$arg" in
    system|overrides) mode="$arg" ;;
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo (from setup-desktop.sh), $HOME is root's home;
# use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# gext is installed by pipx to $real_home/.local/bin; add it to PATH
# when running as root so command -v gext finds it.
if [[ "$EUID" -eq 0 ]] && [[ -d "$real_home/.local/bin" ]]; then
  export PATH="$real_home/.local/bin:$PATH"
fi

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"
# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

if ! command -v gext >/dev/null 2>&1; then
  echo "gext (gnome-extensions-cli) not found" >&2
  echo "  run: ucli install-gnome-extensions-cli" >&2
  exit 1
fi

# Versioned gate. The token is a hash of packages.bash, which is where the
# GNOME_* extension arrays live: as long as those lists do not change, this mode
# has nothing new to install, and gext talks to extensions.gnome.org on every
# call — by far the slowest step in the setup. `--force` re-runs it, e.g. after
# you disable an extension by hand and want the managed set back.
# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/version-script.sh"
gate_name="gnome-extensions-$mode"
gate_version="$(vs_hash "$real_home/.config/ucli/packages.bash")"
if ((!force)) && ! vs_check "$gate_name" user "$gate_version"; then
  echo "GNOME extension set '$mode' unchanged since the last run (${gate_version}); skipping."
  echo "    re-run with --force to apply it anyway: ucli setup-extensions --force"
  exit 0
fi

# Run a command as the real user (not root) when invoked via sudo.
# Extensions and dconf are per-user: as root they would land in root's
# profile/database instead of the user's. HOME is forced too, because dconf
# resolves its database from it.
as_user() {
  if [[ "$EUID" -eq 0 ]] && [[ -n "$SUDO_USER" ]]; then
    runuser -u "$real_user" -- env -u XDG_CONFIG_HOME HOME="$real_home" \
      PATH="$real_home/.local/bin:$PATH" "$@"
  else
    "$@"
  fi
}

run_gext() { as_user gext "$@"; }

# Check if a GNOME extension UUID is already installed.
is_extension_installed() {
  local uuid="$1"
  run_gext list 2>/dev/null | grep -qF "$uuid"
}

# Install an extension from extensions.gnome.org by primary key.
# Skips if the extension UUID is already installed (idempotent re-runs).
install_extension_by_pk() {
  local pk="$1" uuid="$2"

  if [[ -n "$uuid" ]] && is_extension_installed "$uuid"; then
    echo "extension pk=$pk ($uuid) already installed; skipping"
    return 0
  fi

  echo "installing extension pk=$pk ..."
  if ! run_gext install "$pk" >/dev/null 2>&1; then
    echo "warning: could not install extension pk=$pk" >&2
    return 1
  fi
}

# --- enabled-extensions, written once ---------------------------------------

# Current enabled list, one UUID per line.
enabled_extensions() {
  local raw=""
  if command -v dconf >/dev/null 2>&1; then
    raw="$(as_user dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || true)"
  fi
  if [[ -z "$raw" ]] && command -v gsettings >/dev/null 2>&1; then
    raw="$(as_user gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
  fi
  [[ -n "$raw" ]] || return 0
  printf '%s\n' "$raw" | grep -o "'[^']*'" | tr -d "'" || true
}

# enable_uuids <uuid...> — merge into the current list and write it once.
enable_uuids() {
  (($#)) || return 0

  local -a current=() merged=()
  mapfile -t current < <(enabled_extensions)
  ((${#current[@]})) && merged=("${current[@]}")

  local uuid existing
  for uuid in "$@"; do
    [[ -n "$uuid" ]] || continue
    for existing in "${merged[@]:-}"; do
      [[ "$existing" == "$uuid" ]] && continue 2
    done
    merged+=("$uuid")
  done

  local current_joined="" merged_joined=""
  ((${#current[@]})) && current_joined="$(printf '%s,' "${current[@]}")"
  ((${#merged[@]})) && merged_joined="$(printf '%s,' "${merged[@]}")"

  if [[ "$current_joined" == "$merged_joined" ]]; then
    echo "enabled-extensions already up to date (${#merged[@]} entries)"
    return 0
  fi

  local literal="[" i
  for i in "${!merged[@]}"; do
    (( i )) && literal+=", "
    literal+="'${merged[$i]}'"
  done
  literal+="]"

  if command -v dconf >/dev/null 2>&1 &&
     as_user dconf write /org/gnome/shell/enabled-extensions "$literal" 2>/dev/null; then
    echo "  enabled-extensions = $literal"
    return 0
  fi
  if command -v gsettings >/dev/null 2>&1 &&
     as_user gsettings set org.gnome.shell enabled-extensions "$literal" 2>/dev/null; then
    echo "  enabled-extensions = $literal"
    return 0
  fi

  echo "warning: single-write enable failed; falling back to per-extension gext enable" >&2
  local u
  for u in "$@"; do
    [[ -n "$u" ]] || continue
    run_gext enable "$u" >/dev/null 2>&1 || echo "warning: could not enable $u (may need shell restart)" >&2
  done
}

case "$mode" in
  system)
    echo "system GNOME extensions ..."
    # Install anything not packaged by pacman first, then enable in one write.
    for i in "${!GNOME_SYSTEM_EXTENSION_PKS[@]}"; do
      install_extension_by_pk "${GNOME_SYSTEM_EXTENSION_PKS[$i]}" "${GNOME_SYSTEM_EXTENSION_UUIDS[$i]:-}" || true
    done
    enable_uuids "${GNOME_SYSTEM_EXTENSION_UUIDS[@]:-}"
    ;;
  overrides)
    echo "GNOME app overrides ..."
    # App overrides are pacman packages installed by install-packages.sh apps mode.
    # Shell override themes are also pacman packages.
    for i in "${!GNOME_OVERRIDE_EXTENSION_PKS[@]}"; do
      install_extension_by_pk "${GNOME_OVERRIDE_EXTENSION_PKS[$i]}" "${GNOME_OVERRIDE_EXTENSION_UUIDS[$i]:-}" || true
    done
    enable_uuids "${GNOME_OVERRIDE_EXTENSION_UUIDS[@]:-}"
    ;;
  *)
    echo "unknown mode: $mode (use 'system' or 'overrides')" >&2
    usage
    exit 2
    ;;
esac

vs_commit "$gate_name" user "$gate_version"
echo "done. run 'ucli gnome' or restart GNOME Shell (Alt+F2, r, Enter) to apply."
