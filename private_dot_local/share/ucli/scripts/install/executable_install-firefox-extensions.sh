#!/usr/bin/env bash
# Install Firefox extensions from an extensions file.
#
# Usage:
#   install-firefox-extensions.sh <extensions-file>
#
# Downloads XPI files from addons.mozilla.org and places them in each
# Firefox profile's extensions/ directory with the extension ID as filename.
# Firefox detects and installs them on next startup.
#
# This is the reliable userspace method — firefox --install-extension does not
# work with extension IDs (it expects XPI paths) and is finicky with --profile.
# Direct placement into extensions/<id>.xpi is Firefox's documented behavior.
#
# Source: https://dev.to/alanwest/how-to-programmatically-install-firefox-extensions-and-why-it-breaks-2b01
set -uo pipefail

EXT_FILE="${1:?usage: install-firefox-extensions.sh <extensions-file>}"

if [[ ! -r "$EXT_FILE" ]]; then
  echo "error: extensions file not found: $EXT_FILE" >&2
  exit 1
fi

# Find Firefox profile directory (XDG-compliant first, then traditional)
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

PROFILE_DIR=""
if [[ -d "$real_home/.config/mozilla/firefox" ]]; then
  PROFILE_DIR="$real_home/.config/mozilla/firefox"
elif [[ -d "$real_home/.mozilla/firefox" ]]; then
  PROFILE_DIR="$real_home/.mozilla/firefox"
fi

if [[ -z "$PROFILE_DIR" ]]; then
  echo "no Firefox profile found; skipping extensions" >&2
  echo "  launch Firefox once to create a profile, then re-run: ucli apps" >&2
  exit 0
fi

echo "Firefox profile dir: $PROFILE_DIR"

# Collect profile directories from profiles.ini
profile_dirs=()
while IFS= read -r line; do
  path="${line#Path=}"
  if [[ "$path" != "$line" ]]; then
    if [[ "$path" == /* ]]; then
      prof_dir="$path"
    else
      prof_dir="$PROFILE_DIR/$path"
    fi
    if [[ -d "$prof_dir" ]]; then
      profile_dirs+=("$prof_dir")
    fi
  fi
done < <(grep '^Path=' "$PROFILE_DIR/profiles.ini" 2>/dev/null || true)

if ((${#profile_dirs[@]} == 0)); then
  echo "no Firefox profiles found; skipping extensions" >&2
  exit 0
fi

echo "Found ${#profile_dirs[@]} Firefox profile(s)"

# Map extension IDs to AMO slugs for XPI download
declare -A AMO_SLUGS=(
  ["bitwarden-browser-extension@bitwarden.com"]="bitwarden-password-manager"
  ["darkreader@darkreader.org"]="darkreader"
  ["violentmonkey@violentmonkey.net"]="violentmonkey"
  ["react-devtools@mozilla.com"]="react-devtools"
)

# Collect non-empty, non-comment extension IDs
ext_ids=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line//[[:space:]]/}"
  [[ -z "$line" ]] && continue
  ext_ids+=("$line")
done < "$EXT_FILE"

if ((${#ext_ids[@]} == 0)); then
  echo "==> no extensions to install."
  echo "    Restart Firefox to activate new extensions."
  exit 0
fi

# Download XPIs to temp dir
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

declare -A xpi_map  # ext_id -> xpi_path

for ext_id in "${ext_ids[@]}"; do
  slug="${AMO_SLUGS[$ext_id]:-}"
  if [[ -z "$slug" ]]; then
    echo "warning: no AMO slug mapping for $ext_id; skipping" >&2
    continue
  fi

  xpi_url="https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi"
  xpi_file="$tmpdir/${slug}.xpi"

  echo "==> downloading $ext_id ($slug) ..."
  if ! curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" \
       "$xpi_url" -o "$xpi_file" 2>/dev/null; then
    echo "    ERROR: failed to download $ext_id from AMO" >&2
    continue
  fi

  # Verify it's a valid ZIP/XPI
  if ! command -v unzip >/dev/null 2>&1 || ! unzip -t "$xpi_file" >/dev/null 2>&1; then
    echo "    ERROR: downloaded file is not a valid XPI for $ext_id" >&2
    rm -f "$xpi_file"
    continue
  fi

  size="$(du -h "$xpi_file" | cut -f1)"
  echo "    downloaded: $ext_id ($size)"
  xpi_map["$ext_id"]="$xpi_file"
done

if ((${#xpi_map[@]} == 0)); then
  echo "error: no extensions downloaded successfully" >&2
  exit 1
fi

# Place each XPI into each profile's extensions/ dir with extension ID as filename
# Skip extensions already installed in all profiles
total_installed=0
total_skipped=0
total_failed=0

for ext_id in "${!xpi_map[@]}"; do
  xpi_file="${xpi_map[$ext_id]}"
  echo "==> installing $ext_id ..."

  # Skip if XPI already exists in all profiles (idempotent re-runs)
  already_installed=1
  for prof_dir in "${profile_dirs[@]}"; do
    if [[ ! -f "$prof_dir/extensions/${ext_id}.xpi" ]]; then
      already_installed=0
      break
    fi
  done

  if (( already_installed )); then
    echo "    already installed in all profiles; skipping"
    total_skipped=$((total_skipped + 1))
    continue
  fi

  installed_any=0
  for prof_dir in "${profile_dirs[@]}"; do
    ext_dir="$prof_dir/extensions"
    mkdir -p "$ext_dir"
    if cp -f "$xpi_file" "$ext_dir/${ext_id}.xpi" 2>/dev/null; then
      echo "    placed in $ext_dir/${ext_id}.xpi"
      installed_any=1
    else
      echo "    WARNING: failed to place $ext_id in $prof_dir" >&2
    fi
  done

  if (( installed_any )); then
    total_installed=$((total_installed + 1))
  else
    total_failed=$((total_failed + 1))
  fi
done

echo
echo "==> done. $total_installed installed, $total_skipped skipped (already installed), $total_failed failed."
echo "    Restart Firefox to activate new extensions."

echo
echo "==> done. $total_installed installed, $total_failed failed."
echo "    Restart Firefox to activate new extensions."
