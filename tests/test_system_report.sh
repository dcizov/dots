#!/usr/bin/env bash
# system/detect.sh (`ucli profile`) and system-check.sh:
# read-only reports. profile prints the configured chezmoi data and what is
# detected; system-check prints the machine's facts by section.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

detect_report() { ( source ../private_dot_local/share/ucli/scripts/system/executable_detect.sh "$@" ); }
system_check() { ( source ../private_dot_local/share/ucli/scripts/system/executable_system-check.sh "$@" ); }

test_detect_reports_configured_and_detected_values() {
  stub chezmoi 'echo "{\"machine\": \"laptop\", \"desktop\": \"gnome\", \"role\": \"dev\", \"gaming\": false}"'
  stub pacman 'exit 1'
  mkdir -p "$HOME/.config/distrobox"
  echo 'DEVBOX_SSH_PORT=2299' >"$HOME/.config/distrobox/devbox.env"
  export XDG_CURRENT_DESKTOP=GNOME
  t_run detect_report
  assert_status 0
  assert_contains "$T_OUT" "configured.machine: laptop"
  assert_contains "$T_OUT" "configured.desktop: gnome"
  assert_contains "$T_OUT" "configured.devbox_ssh_port: 2299"
  assert_contains "$T_OUT" "detected.desktop_session: gnome"
  assert_contains "$T_OUT" "detected.installed_desktop: none"
  local key
  for key in detected.distro detected.cpu detected.virtualization root.fstype snapper.root limine; do
    assert_contains "$T_OUT" "$key: "
  done
}

test_detect_defaults_without_chezmoi() {
  t_minimal_path
  stub pacman 'exit 1'
  t_run detect_report
  assert_status 0
  assert_contains "$T_OUT" "configured.role: dev"
  assert_contains "$T_OUT" "configured.devbox_ssh_port: 2222"
}

test_system_check_prints_every_section() {
  stub sudo 'exit 1'
  t_run system_check
  assert_status 0
  local section
  for section in os "cpu and memory" "root filesystem" firmware; do
    assert_contains "$T_PLAIN" "$section"
  done
  assert_contains "$T_OUT" "kernel        $(uname -r)"
}

t_main
