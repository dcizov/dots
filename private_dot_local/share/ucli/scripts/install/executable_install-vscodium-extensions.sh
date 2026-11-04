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

# Versioned gate (ported from Bluefin's /usr/lib/ublue/setup-services/libsetup.sh):
# the token is a hash of extensions.txt, so the slow `codium --install-extension`
# loop only runs when the list actually changed. `--force` re-runs it anyway.
# shellcheck source=/dev/null
. "${HOME}/.config/ucli/scripts/lib/version-script.sh"
EXT_VERSION="$(vs_hash "$EXT_FILE")"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1
if (( ! FORCE )) && ! vs_check vscodium-extensions user "$EXT_VERSION"; then
    echo "VSCodium extensions unchanged since the last run (${EXT_VERSION}); skipping."
    echo "    re-run with --force to install again, or edit $EXT_FILE"
    exit 0
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

vs_commit vscodium-extensions user "$EXT_VERSION"

echo "==> done. $count extension entries processed."
echo "    Verify installed list:  codium --list-extensions"
