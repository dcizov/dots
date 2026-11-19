# shellcheck shell=bash
# Small helpers that every script was re-defining. Sourced, never executed.
#
# Lives in lib/ next to ui.sh so a script running under sudo finds it from its
# own path:
#     . "$(dirname "$0")/../lib/common.sh"
#
# What belongs here: things whose body is identical in every caller. Anything
# script-specific (a `usage` text, a `note` with its own column layout) stays in
# the script — a shared helper that has to be told what to print is not shared
# logic, it is a wrapper.

_ucli_common_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
. "$_ucli_common_dir/ui.sh"

# as_root <command...> — run as root, through sudo only when needed. The four
# scripts that install services all had their own copy of this.
as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# have <command> — is the program on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# confirm <prompt> — ask, unless the caller's --yes flag is set. Callers keep
# their own `yes_flag` parsing; this only reads it.
confirm() {
  ((${yes_flag:-0})) && return 0
  ui_confirm "$1"
}

# ucli_real_user / ucli_real_home — the person ucli is acting for. Under sudo
# that is SUDO_USER and their passwd home, not root's; otherwise it is the
# caller and $HOME. Per-user config (~/.config/ucli) and per-user installs must
# use this, never a bare $HOME, or a `sudo ucli …` step reads root's files.
ucli_real_user() { printf '%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"; }
ucli_real_home() {
  local home=""
  if [[ -n "${SUDO_USER:-}" ]]; then
    home="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)"
  fi
  [[ -n "$home" ]] || home="${HOME:-$(getent passwd "$(ucli_real_user)" 2>/dev/null | cut -d: -f6 || true)}"
  printf '%s\n' "$home"
}

# ucli_load_packages [home] — source packages.bash (required: every package
# array lives there) and then the optional per-machine overlay,
# packages.local.bash, which fills PERSONAL_* and overrides settings. Both are
# plain global assignments, so sourcing them here defines them for the caller.
ucli_load_packages() {
  local home="${1:-$(ucli_real_home)}"
  local base="$home/.config/ucli/packages.bash" overlay="$home/.config/ucli/packages.local.bash"
  if [[ ! -r "$base" ]]; then
    printf 'ucli: %s is missing — run: chezmoi apply\n' "$base" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$base"
  if [[ -r "$overlay" ]]; then
    # shellcheck source=/dev/null
    . "$overlay"
  fi
}

# ucli_script_help [first] [last] — print the caller's header comment (lines
# first..last, default 2..the first non-comment line) with the "# " stripped:
# the --help text of every script that documents itself at the top. Reads the
# caller's own file, so it works whether the script was run or sourced.
ucli_script_help() {
  local file="${BASH_SOURCE[1]}" first="${1:-2}" last="${2:-}"
  if [[ -n "$last" ]]; then
    sed -n "${first},${last}p" "$file" | sed 's/^# \{0,1\}//'
  else
    awk -v first="$first" 'NR < first { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$file"
  fi
}
