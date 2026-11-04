# Versioned hook gate for ucli scripts. Sourced, never executed.
#
# Ported from Bluefin's /usr/lib/ublue/setup-services/libsetup.sh, which gates
# the per-user and per-system "setup hooks" so a step runs once per version
# token instead of being guarded by ad-hoc `[[ -f something ]]` probes.
#
# State lives in the XDG state dir, one file per <scope>/<name>:
#   ${XDG_STATE_HOME:-$HOME/.local/state}/ucli/gates/<scope>/<name>
#
# Usage:
#   . "$HOME/.config/ucli/scripts/lib/version-script.sh"
#   if vs_check gnome-extensions user 3; then
#     do_the_work && vs_commit gnome-extensions user 3
#   fi
#
# The version token is just a string: a counter you bump by hand, or a content
# hash ("run again when the config file changes"). vs_check succeeds — i.e. the
# block should run — whenever the stored token differs from the requested one,
# including "never ran". Nothing is committed until the work succeeded, so a
# failed run is retried on the next invocation instead of being skipped forever.

# shellcheck shell=bash

[ -n "${_UCLI_VERSION_SCRIPT_LOADED:-}" ] && return 0
_UCLI_VERSION_SCRIPT_LOADED=1

# The gate registry belongs to the invoking user, not root, even when a script
# is driven through sudo.
_vs_home() {
  local user="${SUDO_USER:-$USER}"
  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    getent passwd "$user" | cut -d: -f6
  else
    printf '%s' "${HOME:-$(getent passwd "$user" | cut -d: -f6)}"
  fi
}

vs_state_dir() {
  local scope="${1:-user}" base
  base="${XDG_STATE_HOME:-$(_vs_home)/.local/state}"
  case "$base" in
    /*) ;;
    *) base="$(_vs_home)/.local/state" ;;
  esac
  printf '%s/ucli/gates/%s' "$base" "$scope"
}

vs_file() { printf '%s/%s' "$(vs_state_dir "${2:-user}")" "$1"; }

# vs_current <name> [scope] — stored version token, empty when never committed.
vs_current() {
  local f
  f="$(vs_file "$1" "${2:-user}")"
  [[ -r "$f" ]] && { head -n1 "$f" 2>/dev/null || true; }
}

# vs_check <name> [scope] <version> — 0 = run the block, 1 = already done.
vs_check() {
  local name="$1" scope="${2:-user}" want="${3:-1}" cur
  [[ -n "$name" && -n "$want" ]] || return 0
  cur="$(vs_current "$name" "$scope")"
  [[ "$cur" != "$want" ]]
}

# vs_commit <name> [scope] <version> — record success.
vs_commit() {
  local name="$1" scope="${2:-user}" ver="${3:-1}" dir f
  dir="$(vs_state_dir "$scope")"
  f="$(vs_file "$name" "$scope")"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$ver" >"$f" 2>/dev/null || return 0
  # keep the gate readable by the real user when we were root
  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER" "$dir" 2>/dev/null || true
  fi
}

# vs_forget <name> [scope] — force the block to run again next time.
vs_forget() { rm -f "$(vs_file "$1" "${2:-user}")" 2>/dev/null || true; }

# vs_list — "scope name version" for every committed gate.
vs_list() {
  local base f
  base="${XDG_STATE_HOME:-$(_vs_home)/.local/state}/ucli/gates"
  [[ -d "$base" ]] || return 0
  while IFS= read -r f; do
    printf '%s\t%s\t%s\n' \
      "$(basename "$(dirname "$f")")" \
      "$(basename "$f")" \
      "$(head -n1 "$f" 2>/dev/null)"
  done < <(find "$base" -type f -name '*' 2>/dev/null | sort)
}

# vs_hash <file>... — short content hash, handy as a version token.
vs_hash() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(cat "$@" 2>/dev/null | sha256sum | cut -c1-12)"
  else
    out="$(cat "$@" 2>/dev/null | cksum | tr ' ' '-')"
  fi
  printf '%s' "$out"
}
