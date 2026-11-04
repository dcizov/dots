#!/usr/bin/env bash
# Install Firefox extensions from an extensions file.
#
# Usage:
#   install-firefox-extensions.sh <extensions-file>
#
# Reads extension IDs from the file and installs them via
# `firefox --install-extension <id>`. Skips extensions already installed.
#
# Source: https://support.mozilla.org/en-US/kb/install-add-ons-from-files
set -euo pipefail

EXT_FILE="${1:?usage: install-firefox-extensions.sh <extensions-file>}"

if [[ ! -r "$EXT_FILE" ]]; then
  echo "error: extensions file not found: $EXT_FILE" >&2
  exit 1
fi

if ! command -v firefox >/dev/null 2>&1; then
  echo "error: firefox not found on PATH" >&2
  exit 1
fi

# When run via sudo, use the invoking user's Firefox profile
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

count=0
skipped=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # Strip comments and whitespace
  line="${line%%#*}"
  line="${line//[[:space:]]/}"
  [[ -z "$line" ]] && continue

  ext_id="$line"

  echo "==> installing $ext_id ..."
  if firefox --install-extension "$ext_id" >/dev/null 2>&1; then
    echo "    installed: $ext_id"
    count=$((count + 1))
  else
    echo "    warning: failed to install $ext_id (may already be installed or ID may be wrong)" >&2
    skipped=$((skipped + 1))
  fi
done < "$EXT_FILE"

echo
echo "==> done. $count installed, $skipped skipped/failed."
echo "    Restart Firefox to activate new extensions."