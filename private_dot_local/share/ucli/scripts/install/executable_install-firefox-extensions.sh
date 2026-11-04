#!/usr/bin/env bash
# Install Firefox extensions from an extensions file.
#
# Usage:
#   install-firefox-extensions.sh <extensions-file>
#
# Downloads XPI files from addons.mozilla.org and installs them into each
# Firefox profile using `firefox --install-extension <xpi-path>`.
#
# `firefox --install-extension <id>` does NOT work with extension IDs — it
# expects XPI file paths. Downloading XPIs first is the reliable method.
#
# Source: https://dev.to/alanwest/how-to-programmatically-install-firefox-extensions-and-why-it-breaks-2b01
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

echo "Firefox profile dir: $PROFILE_DIR"

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

xpi_paths=()

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
    echo "    warning: failed to download $ext_id from AMO" >&2
    continue
  fi

  # Verify it's a valid ZIP/XPI
  if ! command -v unzip >/dev/null 2>&1 || ! unzip -t "$xpi_file" >/dev/null 2>&1; then
    echo "    warning: downloaded file is not a valid XPI for $ext_id" >&2
    rm -f "$xpi_file"
    continue
  fi

  echo "    downloaded: $ext_id ($(du -h "$xpi_file" | cut -f1))"
  xpi_paths+=("$xpi_file")
done

if ((${#xpi_paths[@]} == 0)); then
  echo "error: no extensions downloaded successfully" >&2
  exit 1
fi

# Install all XPIs in a single Firefox launch
echo "==> installing ${#xpi_paths[@]} extension(s) via firefox --install-extension ..."
if firefox --install-extension "${xpi_paths[@]}" >/dev/null 2>&1; then
  echo "    all extensions installed successfully"
else
  echo "warning: batch install failed, trying individually..." >&2
  for xpi in "${xpi_paths[@]}"; do
    if firefox --install-extension "$xpi" >/dev/null 2>&1; then
      echo "    installed: $xpi"
    else
      echo "    warning: failed to install $xpi" >&2
    fi
  done
fi

echo
echo "==> done. Restart Firefox to activate new extensions."
