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
