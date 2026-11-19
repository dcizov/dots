#!/usr/bin/env bash
# install-sync.sh: syncthing installed once, syncthing@<user> enabled, and
# this machine's device ID — from syncthing itself, not the first device in a
# config that also lists the paired ones.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

sync_i() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-sync.sh "$@" ); }

MINE="AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH"
PEER="ZZZZZZZ-YYYYYYY-XXXXXXX-WWWWWWW-VVVVVVV-UUUUUUU-TTTTTTT-SSSSSSS"

world() {
  export USER=alice
  stub sudo '"$@"'
  stub pacman
  stub systemctl 'case $1 in is-enabled) exit 0 ;; is-active) echo active ;; esac; exit 0'
  stub sleep
  mkdir -p "$HOME/.local/state/syncthing"
  # a paired machine: the peer's <device> comes first in the folder entry
  printf '<configuration>\n<folder id="sync"><device id="%s"></device><device id="%s"></device></folder>\n</configuration>\n' \
    "$PEER" "$MINE" >"$HOME/.local/state/syncthing/config.xml"
}

test_install_enable_and_report_this_machines_id() {
  world
  stub syncthing "[[ \$1 == device-id ]] && echo $MINE"
  rm "$T_BIN/syncthing"   # not installed yet: pacman installs it
  t_run sync_i
  assert_status 0
  assert_called "pacman -S --needed --noconfirm syncthing"
  assert_called "systemctl enable --now syncthing@alice.service"
}

test_the_device_id_comes_from_syncthing_not_the_first_config_entry() {
  world
  stub syncthing "[[ \$1 == device-id ]] && echo $MINE; exit 0"
  t_run sync_i
  assert_contains "$T_OUT" "syncthing: already installed"
  assert_contains "$T_OUT" "$MINE"
  assert_not_contains "$T_OUT" "$PEER"
}

test_syncthing_1x_answers_to_the_old_flag() {
  world
  stub syncthing "[[ \$1 == --device-id ]] && echo $MINE || exit 1"
  t_run sync_i --status
  assert_contains "$T_OUT" "device id   : $MINE"
  assert_contains "$T_OUT" "service     : active"
}

test_no_service_and_a_config_only_fallback() {
  world
  stub syncthing 'exit 1'
  rm "$HOME/.local/state/syncthing/config.xml"
  mkdir -p "$HOME/.config/syncthing"
  printf '<device id="%s">\n' "$MINE" >"$HOME/.config/syncthing/config.xml"
  t_run sync_i --no-service
  assert_status 0
  assert_not_called "systemctl enable"
  assert_contains "$T_OUT" "$MINE"
}

test_arguments() {
  t_run sync_i --bogus
  assert_status 2
  t_run sync_i --help
  assert_contains "$T_OUT" "Usage: install-sync.sh [--no-service] [--status]"
}

t_main
