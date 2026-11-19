#!/usr/bin/env bash
# install-gradia-capture.sh: fetch the pinned commit, run its build.sh, install
# the zip with gnome-extensions, verify the directory, and gate on the commit —
# but rebuild when the gate says done and the directory is gone.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

gradia() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-gradia-capture.sh "$@" ); }

UUID=gradia-integration@alexandervanhee.github.io
EXT() { printf '%s' "$HOME/.local/share/gnome-shell/extensions/$UUID"; }

# toolchain [build-ok 0|1] — git "fetches" a checkout whose build.sh makes the
# zip; gnome-extensions install unpacks it into the user's extension dir.
toolchain() {
  stub zip
  stub git "if [[ \$1 == -C && \$3 == checkout ]]; then
      printf '#!/bin/sh\n[ ${1:-1} = 1 ] || exit 1\ntouch $UUID.shell-extension.zip\n' >\"\$2/build.sh\"; chmod +x \"\$2/build.sh\"
    elif [[ \$1 == -C && \$3 == fetch ]]; then [[ \${FAKE_FETCH:-1} == 1 ]]
    elif [[ \$1 == init ]]; then mkdir -p \"\${@: -1}\"
    fi"
  stub gnome-extensions "[[ \$1 == install ]] && mkdir -p \"\$HOME/.local/share/gnome-shell/extensions/$UUID\"; exit 0"
}

test_the_pinned_commit_is_built_and_installed() {
  toolchain
  t_run gradia
  assert_status 0
  assert_called "git -C"
  assert_contains "$(grep 'fetch' "$T_CALLS")" "0b7e47e1e5c1e68e234e4d2d24b307e1da1d18a9"
  assert_called "gnome-extensions install --force"
  assert_file "$(EXT)"
  assert_contains "$T_OUT" "ok: $UUID installed"
}

test_the_gate_skips_and_a_missing_directory_rebuilds() {
  toolchain
  gradia >/dev/null 2>&1
  t_run gradia
  assert_contains "$T_OUT" "already installed; skipping"
  rm -rf "$(EXT)"
  t_run gradia
  assert_contains "$T_OUT" "is missing; rebuilding"
  assert_file "$(EXT)"
}

test_each_failure_stops_without_recording() {
  toolchain 0
  t_run gradia
  assert_status 1
  assert_contains "$T_OUT" "build.sh failed"
  toolchain
  export FAKE_FETCH=0
  t_run gradia
  assert_status 1
  assert_contains "$T_OUT" "could not fetch commit"
  export FAKE_FETCH=1
  stub gnome-extensions 'exit 0'
  t_run gradia
  assert_status 1
  assert_contains "$T_OUT" "install reported success but"
  [[ -z "$(ls "$XDG_STATE_HOME/ucli/gates/user" 2>/dev/null)" ]] || t_die "a failed build must not commit the gate"
}

test_missing_tools_are_named() {
  t_minimal_path
  t_run gradia
  assert_contains "$T_OUT" "gnome-extensions not found"
  stub gnome-extensions; stub git
  t_run gradia
  assert_contains "$T_OUT" "zip not found"
  t_run gradia --bogus
  assert_status 2
}

t_main
