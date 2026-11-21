# shellcheck shell=bash
# Test harness for the ucli shell scripts, sourced by tests/test_*.sh.
#
# A test file defines test_* functions and ends with `t_main`. Each test runs
# in its own subshell, inside a fresh sandbox:
#   HOME, XDG_*_HOME   under a temp dir: nothing reads or writes the real ~
#   $T_BIN             first on PATH; `stub` writes fake commands into it
#   $T_CALLS           one line per stub invocation: "name arg…"
# Code under test is sourced by a path relative to tests/ (in a subshell, so
# its `exit` and `set -e` stay contained), which is why everything runs from
# tests/: `source ../private_dot_local/…` then resolves the same way for bash,
# for shellcheck (source-path=SCRIPTDIR) and for desloppify's import graph.
# Assertions print what differed and stop the current test.

T_TESTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$T_TESTS" || exit 1

# Source trees, relative to tests/ (read by the test files).
export T_SCRIPTS="../private_dot_local/share/ucli/scripts"
export T_CONFIG="../private_dot_config/ucli"

t_die() { printf '    %s\n' "$@" >&2; exit 1; }

assert_eq() {
  [[ "$1" == "$2" ]] || t_die "${3:-values differ}" "expected: $1" "actual:   $2"
}
assert_status() {
  [[ "$T_STATUS" == "$1" ]] || t_die "exit status $T_STATUS, expected $1" "output:" "$T_OUT"
}
assert_contains() {
  [[ "$1" == *"$2"* ]] || t_die "missing: $2" "in:" "$1"
}
assert_not_contains() {
  [[ "$1" != *"$2"* ]] || t_die "unexpected: $2" "in:" "$1"
}
assert_called() {
  grep -qF -- "$1" "$T_CALLS" || t_die "not called: $1" "calls:" "$(cat "$T_CALLS")"
}
assert_not_called() {
  if grep -qF -- "$1" "$T_CALLS"; then t_die "called unexpectedly: $1" "calls:" "$(cat "$T_CALLS")"; fi
}
assert_file() { [[ -e "$1" ]] || t_die "missing file: $1"; }
assert_no_file() { [[ ! -e "$1" ]] || t_die "file should not exist: $1"; }

# t_run <cmd…> — run in a subshell, capturing combined output in T_OUT (and in
# T_PLAIN without ANSI colours) and the exit status in T_STATUS, without
# stopping the test on failure. Deliberately
# not `T_OUT=$(cmd) || T_STATUS=$?`: bash ignores `set -e` anywhere inside an
# || list, so a sourced script would no longer stop at its first failure.
t_run() {
  ( "$@" ) >"$T_ROOT/t_run.out" 2>&1
  T_STATUS=$?
  T_OUT="$(cat "$T_ROOT/t_run.out")"
  # shellcheck disable=SC2034  # read by the test files
  T_PLAIN="$(sed 's/\x1b\[[0-9;]*m//g' "$T_ROOT/t_run.out")"
}

# stub <name> [body] — a fake command on PATH that records its arguments and
# then runs body (bash, default `exit 0`).
stub() {
  local name="$1" body="${2:-exit 0}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "%s $*" >>"$T_CALLS"\n' "$name"
    printf '%s\n' "$body"
  } >"$T_BIN/$name"
  chmod +x "$T_BIN/$name"
}

# t_minimal_path — PATH becomes the stub dir plus a dir holding only the basic
# tools a script needs to run at all, so `command -v X` answers from the test's
# stubs, never from whatever the host happens to have installed.
T_BASICS=(bash sh env cat grep sed awk find head tail wc tr cut sort uniq basename
  dirname mkdir rm cp mv ln touch chmod stat id getent uname date mktemp ls readlink
  realpath tee xargs cmp diff sleep printf test true false seq install timeout)
t_minimal_path() {
  local tool real
  mkdir -p "$T_ROOT/basics"
  for tool in "${T_BASICS[@]}"; do
    real="$(PATH="/usr/bin:/bin" command -v "$tool" 2>/dev/null)" || continue
    [[ "$real" == /* ]] && ln -sf "$real" "$T_ROOT/basics/$tool"
  done
  export PATH="$T_BIN:$T_ROOT/basics"
}

# t_deployed <area>/<name> — copy scripts/<area>/executable_<name>.sh to its
# deployed name under $T_ROOT/scripts (with a copy of lib/), for scripts that
# call their siblings by deployed name; prints the copy's path. Siblings it
# calls can then be faked next to it. Tests still source the real file for
# everything that needs no sibling.
t_deployed() {
  local area="${1%/*}" name="${1#*/}" d="$T_ROOT/scripts"
  mkdir -p "$d/$area"
  # A copy, never a link: a test that fakes a lib file must not be able to
  # write through into the repository.
  [[ -e "$d/lib" ]] || cp -R "$T_SCRIPTS/lib" "$d/lib"
  cp "$T_SCRIPTS/$area/executable_$name.sh" "$d/$area/$name.sh"
  chmod +x "$d/$area/$name.sh"
  printf '%s\n' "$d/$area/$name.sh"
}

# t_fake_script <path> [body] — an executable that records "<basename> args"
# in T_CALLS and runs body (default: succeed).
t_fake_script() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >>"$T_CALLS"\n%s\n' "${1##*/}" "${2:-exit 0}" >"$1"
  chmod +x "$1"
}

# t_config_file <name> — write stdin to ~/.config/ucli/<name> in the sandbox.
t_config_file() {
  mkdir -p "$HOME/.config/ucli"
  cat >"$HOME/.config/ucli/$1"
}

t_sandbox() {
  T_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ucli-test.XXXXXX")"
  trap t_cleanup EXIT
  export HOME="$T_ROOT/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CACHE_HOME="$HOME/.cache" XDG_DATA_HOME="$HOME/.local/share"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
  T_BIN="$T_ROOT/bin"
  mkdir -p "$T_BIN"
  export PATH="$T_BIN:$PATH"
  export T_CALLS="$T_ROOT/calls"
  : >"$T_CALLS"
  # Nothing from the host session: its shell framework and desktop would leak
  # into what the scripts detect.
  unset SUDO_USER ZSH ZSH_CUSTOM XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION \
    DBUS_SESSION_BUS_ADDRESS SSH_CONNECTION
  export UCLI_NO_LINKS=1 NO_COLOR=1
}

t_cleanup() {
  case "${T_ROOT:-}" in
    */ucli-test.*) rm -rf -- "$T_ROOT" ;;
  esac
}

# t_main — run every test_* function defined by the file, report, and exit
# non-zero when any failed.
t_main() {
  local fn log rc pass=0 fail=0
  log="$(mktemp "${TMPDIR:-/tmp}/ucli-test-log.XXXXXX")"
  for fn in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    # Not `if ( … )`: an if condition disables set -e for everything inside it,
    # including the scripts the test sources.
    ( t_sandbox; "$fn" ) >"$log" 2>&1
    rc=$?
    if ((rc == 0)); then
      pass=$((pass + 1))
      printf 'ok    %s\n' "$fn"
    else
      fail=$((fail + 1))
      printf 'FAIL  %s\n' "$fn"
      sed 's/^/      /' "$log"
    fi
  done
  rm -f -- "$log"
  printf '%s: %d passed, %d failed\n\n' "${0##*/}" "$pass" "$fail"
  ((fail == 0))
}
