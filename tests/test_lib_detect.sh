#!/usr/bin/env bash
# lib/detect.sh: normalising, chezmoi data overrides, the desktop from the
# session or from installed packages, os-release, and the hardware probes.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

detect() { source ../private_dot_local/share/ucli/scripts/lib/detect.sh; }

data() { stub chezmoi "echo '$1'"; }

test_norm_lowercases_and_underscores() {
  detect
  assert_eq "kde_plasma" "$(ucli_norm KDE-Plasma)"
}

test_profile_values_come_from_chezmoi_data_with_fallbacks() {
  detect
  data '{"role": "dev-gaming", "gaming": true, "desktop": null}'
  assert_eq "dev-gaming" "$(ucli_profile_value role minimal)"
  assert_eq "True" "$(ucli_profile_value gaming false)"
  assert_eq "auto" "$(ucli_profile_value desktop auto)" "null falls back"
  assert_eq "x" "$(ucli_profile_value missing x)"
  data 'not json'
  assert_eq "dev" "$(ucli_profile_value role dev)"
  t_minimal_path
  assert_eq "dev" "$(ucli_profile_value role dev)" "no chezmoi at all"
}

test_role_and_gaming_defaults() {
  detect; t_minimal_path
  assert_eq "dev" "$(detect_role)"
  assert_eq "false" "$(detect_gaming)"
}

test_the_session_names_the_desktop() {
  detect
  XDG_CURRENT_DESKTOP=ubuntu:GNOME; assert_eq gnome "$(detect_desktop_session)"
  XDG_CURRENT_DESKTOP=KDE; assert_eq kde "$(detect_desktop_session)"
  unset XDG_CURRENT_DESKTOP; DESKTOP_SESSION=plasma; assert_eq kde "$(detect_desktop_session)"
  DESKTOP_SESSION=Hyprland; assert_eq hyprland "$(detect_desktop_session)"
  unset DESKTOP_SESSION; assert_eq none "$(detect_desktop_session)"
}

test_installed_desktop_is_none_one_or_ambiguous() {
  detect
  stub pacman '[[ " ${FAKE_DE:-} " == *" $2 "* ]]'
  assert_eq none "$(detect_installed_desktop)"
  FAKE_DE="gnome-shell" assert_eq gnome "$(FAKE_DE=gnome-shell detect_installed_desktop)"
  assert_eq kde "$(FAKE_DE=plasma-meta detect_installed_desktop)"
  local out rc=0
  out="$(FAKE_DE="gnome-shell hyprland" detect_installed_desktop)" || rc=$?
  assert_eq "ambiguous:gnome hyprland" "$out"
  assert_eq 1 "$rc"
}

test_detect_desktop_prefers_chezmoi_then_session_then_packages() {
  detect
  stub pacman '[[ $2 == hyprland ]]'
  data '{"desktop": "gnome"}'
  XDG_CURRENT_DESKTOP=KDE
  assert_eq gnome "$(detect_desktop)"
  data '{"desktop": "auto"}'
  assert_eq kde "$(detect_desktop)"
  unset XDG_CURRENT_DESKTOP
  assert_eq hyprland "$(detect_desktop)"
}

test_distro_reads_os_release_below_the_test_root() {
  detect
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
  printf 'NAME="CachyOS Linux"\nID=cachyos\nID_LIKE=arch\n' >"$UCLI_ETC_ROOT/etc/os-release"
  stub chezmoi 'exit 1'   # no chezmoi data yet
  assert_eq cachyos "$(detect_distro)"
  assert_eq arch "$(detect_distro_like)"
  assert_eq "CachyOS Linux" "$(os_release_field NAME)"
  data '{"distro": "arch"}'
  assert_eq arch "$(detect_distro)" "a chezmoi override wins"
  assert_eq cachyos "$(detect_distro_raw)" "the raw value never does"
}

test_virtualization_prints_one_answer() {
  detect
  stub systemd-detect-virt 'echo none; exit 1'
  assert_eq none "$(detect_virtualization)"
  stub systemd-detect-virt 'echo kvm'
  assert_eq kvm "$(detect_virtualization)"
}

test_snapper_and_limine_presence() {
  detect
  t_minimal_path
  local rc=0
  [[ "$(detect_limine || true)" == missing ]] || t_die "limine should be missing"
  detect_limine >/dev/null || rc=$?
  assert_eq 1 "$rc"
  stub limine-update
  assert_eq ok "$(detect_limine)"
}

test_fingerprint_reader_by_usb_id() {
  detect
  stub lsusb 'echo "Bus 001 Device 003: ID 06cb:00bd Synaptics, Inc. Prometheus MIS Touch Fingerprint Reader"'
  assert_eq yes "$(detect_fingerprint)"
}

t_main
