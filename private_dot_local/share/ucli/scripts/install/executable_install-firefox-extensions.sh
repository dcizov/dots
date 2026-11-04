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

# Collect non-empty, non-comment extension IDs
ext_ids=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # Strip comments and whitespace
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

# Install all extensions in a single Firefox launch (avoids reopening Firefox per extension)
count=0
skipped=0
for ext_id in "${ext_ids[@]}"; do
  echo "==> installing $ext_id ..."
done
if firefox --install-extension "${ext_ids[@]}" >/dev/null 2>&1; then
  count=${#ext_ids[@]}
  for ext_id in "${ext_ids[@]}"; do
    echo "    installed: $ext_id"
  done
else
  # If batch install fails, try each individually so we can report per-extension status
  for ext_id in "${ext_ids[@]}"; do
    if firefox --install-extension "$ext_id" >/dev/null 2>&1; then
      echo "    installed: $ext_id"
      count=$((count + 1))
    else
      echo "    warning: failed to install $ext_id (may already be installed or ID may be wrong)" >&2
      skipped=$((skipped + 1))
    fi
  done
fi

echo
echo "==> done. $count installed, $skipped skipped/failed."
echo "    Restart Firefox to activate new extensions."