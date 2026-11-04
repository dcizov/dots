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
# firefox --install-extension <id> does NOT work with extension IDs — it
# expects XPI file paths. Direct profile placement is the reliable userspace
# method (see https://dev.to/alanwest/how-to-programmatically-install-firefox-extensions-and-why-it-breaks-2b01).
#
set -euo pipefail

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

# Download XPIs and install into each profile
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

count=0
skipped=0

for ext_id in "${ext_ids[@]}"; do
  slug="${AMO_SLUGS[$ext_id]:-}"
  if [[ -z "$slug" ]]; then
    echo "warning: no AMO slug mapping for $ext_id; skipping" >&2
    skipped=$((skipped + 1))
    continue
  fi

  xpi_url="https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi"
  xpi_file="$tmpdir/${ext_id}.xpi"

  echo "==> downloading $ext_id ..."
  if ! curl -fsSL "$xpi_url" -o "$xpi_file" 2>/dev/null; then
    echo "    warning: failed to download $ext_id from AMO" >&2
    skipped=$((skipped + 1))
    continue
  fi
  echo "    downloaded: $ext_id"

  # Install into each Firefox profile (filename must be extension ID)
  profiles_found=0
  while IFS= read -r line; do
    path="${line#Path=}"
    if [[ "$path" != "$line" ]]; then
      if [[ "$path" == /* ]]; then
        prof_dir="$path"
      else
        prof_dir="$PROFILE_DIR/$path"
      fi
      if [[ -d "$prof_dir" ]]; then
        ext_dir="$prof_dir/extensions"
        mkdir -p "$ext_dir"
        cp -f "$xpi_file" "$ext_dir/${ext_id}.xpi"
        echo "    installed to $prof_dir/extensions/${ext_id}.xpi"
        profiles_found=1
      fi
    fi
  done < <(grep '^Path=' "$PROFILE_DIR/profiles.ini" 2>/dev/null || true)

  if (( profiles_found )); then
    count=$((count + 1))
  else
    echo "    warning: no Firefox profiles found for $ext_id" >&2
    skipped=$((skipped + 1))
  fi
done

echo
echo "==> done. $count installed, $skipped skipped/failed."
echo "    Restart Firefox to activate new extensions."
