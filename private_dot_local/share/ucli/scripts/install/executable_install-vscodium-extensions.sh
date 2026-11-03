#!/usr/bin/env bash
# ============================================================================
# install-vscodium-extensions.sh
#
# Installs the VSCodium extensions listed in the chezmoi-managed
# ~/.config/VSCodium/User/extensions.txt on the HOST (VSCodium runs on the
# host, not inside the dev box).
#
# Usage:
#   ~/.local/share/ucli/scripts/install/executable_install-vscodium-extensions.sh
#   # or via ucli:   ucli install-vscodium-ext
#
# Lines starting with '#' are ignored.
# ============================================================================

set -euo pipefail

EXT_FILE="${HOME}/.config/VSCodium/User/extensions.txt"

if [[ ! -r "$EXT_FILE" ]]; then
    echo "error: extensions file not found: $EXT_FILE" >&2
    echo "       re-run: chezmoi apply -v" >&2
    exit 1
fi

if ! command -v codium >/dev/null 2>&1; then
    echo "error: 'codium' not found on PATH." >&2
    echo "       Install VSCodium first (see packages.bash: ucli install-dev)." >&2
    exit 1
fi

count=0
while IFS= read -r line || [[ -n "$line" ]]; do
    # strip leading/trailing whitespace, skip blanks and comments
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue

    echo "==> installing $line"
    codium --install-extension "$line" || echo "    (failed or already present: $line)"
    count=$((count + 1))
done < "$EXT_FILE"

echo "==> done. $count extension entries processed."
echo "    Verify installed list:  codium --list-extensions"
