#!/usr/bin/env bash
# arch-snapper-limine.sh (`ucli setup-snapshots`): the gates before anything is
# configured — Arch family only, CachyOS left alone, btrfs with the four
# subvolumes — and a dry run that installs nothing.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

snapper_setup() { ( source ../private_dot_local/share/ucli/scripts/system/executable_arch-snapper-limine.sh "$@" ); }

# box <ID> [ID_LIKE] [fstype] [subvolumes…]
box() {
  export UCLI_TEST_ROOT="$T_ROOT" UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
  printf 'ID=%s\nID_LIKE=%s\n' "$1" "${2:-}" >"$UCLI_ETC_ROOT/etc/os-release"
  stub findmnt "echo ${3:-btrfs}"
  local vols="${*:4}"; [[ -n "$vols" ]] || vols="@ @home @log @pkg"
  local list="" v i=256
  for v in $vols; do list+="ID $i gen 1 top level 5 path $v"$'\n'; i=$((i + 1)); done
  printf '%s' "$list" >"$T_ROOT/subvols"
  stub btrfs 'cat "${T_CALLS%/*}/subvols"'
  stub pacman
}

test_non_arch_systems_are_refused() {
  box ubuntu debian
  t_run snapper_setup --dry-run
  assert_status 1
  assert_contains "$T_OUT" "unsupported: ID=ubuntu is not Arch-based"
}

test_cachyos_is_left_alone_unless_forced() {
  box cachyos arch
  t_run snapper_setup --dry-run
  assert_status 0
  assert_contains "$T_OUT" "CachyOS detected: the Snapper + Limine stack is installer-owned"
  assert_not_called "pacman"
}

test_derivatives_continue_with_a_note() {
  box endeavouros arch ext4
  t_run snapper_setup --dry-run
  assert_contains "$T_OUT" "ID=endeavouros is Arch-based (ID_LIKE=arch)"
  assert_contains "$T_OUT" "Root filesystem is not btrfs; refusing."
  assert_status 1
}

test_a_missing_subvolume_is_named() {
  box arch "" btrfs @ @home @log
  t_run snapper_setup --dry-run
  assert_status 1
  assert_contains "$T_OUT" "Required Btrfs subvolume missing: @pkg"
}

test_a_dry_run_only_asks_which_aur_helper() {
  box arch
  S="$(t_deployed system/arch-snapper-limine)"
  t_fake_script "${S%/*}/../install/install-aur-helper.sh" 'echo paru'
  t_run bash "$S" --dry-run --yes
  assert_called "install-aur-helper.sh --print-only"
  assert_not_called "install-aur-helper.sh --yes"
  assert_not_called "pacman -S"
  assert_contains "$T_OUT" "+ pacman -S --needed --noconfirm btrfs-progs snapper snap-pac limine"
}

test_arguments() {
  t_run snapper_setup --bogus
  assert_status 2
  t_run snapper_setup --help
  assert_contains "$T_OUT" "usage: sudo arch-snapper-limine.sh"
}

t_main
