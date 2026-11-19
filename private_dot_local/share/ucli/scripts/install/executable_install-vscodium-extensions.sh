#!/usr/bin/env bash
# ============================================================================
# install-vscodium-extensions.sh
#
# Installs the VSCodium extensions listed in the chezmoi-managed
# ~/.config/VSCodium/User/extensions.txt on the HOST (VSCodium runs on the
# host, not inside the dev box).
#
# Usage:
#   ucli vscodium-extensions [--force]
#   (~/.local/share/ucli/scripts/install/install-vscodium-extensions.sh)
#
# Lines starting with '#' are ignored.
# ============================================================================

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/version-script.sh
. "$script_dir/../lib/version-script.sh"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) echo "unknown argument: $arg (usage: ucli vscodium-extensions [--force])" >&2; exit 2 ;;
    esac
done

EXT_FILE="${HOME}/.config/VSCodium/User/extensions.txt"

if [[ ! -r "$EXT_FILE" ]]; then
    echo "error: extensions file not found: $EXT_FILE" >&2
    echo "       re-run: chezmoi apply -v" >&2
    exit 1
fi

if ! command -v codium >/dev/null 2>&1; then
    echo "error: 'codium' not found on PATH." >&2
    echo "       Install VSCodium first: ucli devmode (or ucli setup-system) ships it." >&2
    exit 1
fi

# Versioned gate (ported from Bluefin's /usr/lib/ublue/setup-services/libsetup.sh):
# the token is a hash of extensions.txt, so the slow `codium --install-extension`
# loop only runs when the list actually changed. `--force` re-runs it anyway.
EXT_VERSION="$(vs_hash "$EXT_FILE")"
if (( ! FORCE )) && ! vs_check vscodium-extensions user "$EXT_VERSION"; then
    echo "VSCodium extensions unchanged since the last run (${EXT_VERSION}); skipping."
    echo "    re-run with --force to install again, or edit $EXT_FILE"
    exit 0
fi

count=0
failed=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # strip leading/trailing whitespace, skip blanks and comments
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue

    echo "==> installing $line"
    # An extension that is already installed exits 0, so a failure is real
    # (offline, a typo, gone from Open VSX) and must not be remembered as done.
    codium --install-extension "$line" || failed+=("$line")
    count=$((count + 1))
done < "$EXT_FILE"

if ((${#failed[@]})); then
    echo "==> $count extension entries processed; failed: ${failed[*]}" >&2
    echo "    nothing recorded as done: the next run retries" >&2
    exit 1
fi
vs_commit vscodium-extensions user "$EXT_VERSION"

echo "==> done. $count extension entries processed."
echo "    Verify installed list:  codium --list-extensions"
