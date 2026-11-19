#!/usr/bin/env bash
# setup-boot.sh (`ucli setup-boot`): append KERNEL_CMDLINE_EXTRA to every
# limine layout without replacing or duplicating anything, add the plymouth
# hook, refuse bootloaders it does not know. UCLI_ETC_ROOT roots /etc and /boot
# in the sandbox; UCLI_DRY_RUN_ONLY keeps mkinitcpio/limine-update printed only.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

boot() { ( source ../private_dot_local/share/ucli/scripts/system/executable_setup-boot.sh "$@" ); }

machine() {
  export UCLI_ETC_ROOT="$T_ROOT/root" UCLI_DRY_RUN_ONLY=1
  mkdir -p "$UCLI_ETC_ROOT/etc/default" "$UCLI_ETC_ROOT/boot"
  t_config_file packages.bash <<<'KERNEL_CMDLINE_EXTRA=(quiet splash loglevel=3)
PLYMOUTH_THEME=""'
  stub plymouth; stub plymouth-set-default-theme 'echo bgrt'
  stub mkinitcpio; stub limine-update
  printf 'HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)\n' >"$UCLI_ETC_ROOT/etc/mkinitcpio.conf"
}
DEFAULTS() { printf '%s' "$UCLI_ETC_ROOT/etc/default/limine"; }

test_default_limine_gets_only_the_missing_tokens() {
  machine
  echo 'KERNEL_CMDLINE[default]+="root=UUID=abcd rw quiet"' >"$(DEFAULTS)"
  t_run boot --yes
  assert_status 0
  local line; line="$(grep 'KERNEL_CMDLINE' "$(DEFAULTS)")"
  assert_contains "$line" "root=UUID=abcd rw quiet"
  assert_contains "$line" "splash"
  assert_contains "$line" "loglevel=3"
  assert_eq 1 "$(grep -o 'quiet' <<<"$line" | wc -l)" "an existing token is not added twice"
}

test_a_second_run_changes_nothing() {
  machine
  echo 'KERNEL_CMDLINE[default]+="root=UUID=abcd rw"' >"$(DEFAULTS)"
  boot --yes >/dev/null 2>&1
  cp "$(DEFAULTS)" "$T_ROOT/after-first"
  t_run boot --yes
  assert_status 0
  assert_eq "$(cat "$T_ROOT/after-first")" "$(cat "$(DEFAULTS)")"
}

test_limine_conf_cmdlines_are_edited_in_place() {
  machine
  printf 'timeout: 3\n/Arch Linux\n    protocol: linux\n    cmdline: root=UUID=abcd rw\n' >"$UCLI_ETC_ROOT/boot/limine.conf"
  t_run boot --yes
  assert_status 0
  assert_contains "$(cat "$UCLI_ETC_ROOT/boot/limine.conf")" "cmdline: root=UUID=abcd rw quiet splash loglevel=3"
  assert_contains "$(cat "$UCLI_ETC_ROOT/boot/limine.conf")" "timeout: 3"
}

test_the_plymouth_hook_is_added_once() {
  machine
  echo 'KERNEL_CMDLINE[default]+="rw"' >"$(DEFAULTS)"
  boot --yes >/dev/null 2>&1
  boot --yes >/dev/null 2>&1
  local hooks; hooks="$(cat "$UCLI_ETC_ROOT/etc/mkinitcpio.conf")"
  assert_contains "$hooks" "plymouth"
  assert_eq 1 "$(grep -o plymouth <<<"$hooks" | wc -l)"
}

test_no_plymouth_drops_splash_when_plymouth_is_absent() {
  machine
  rm "$T_BIN/plymouth"
  echo 'KERNEL_CMDLINE[default]+="rw"' >"$(DEFAULTS)"
  t_run boot --no-plymouth --yes
  assert_status 0
  assert_not_contains "$(cat "$(DEFAULTS)")" "splash"
  assert_contains "$(cat "$(DEFAULTS)")" "loglevel=3"
}

test_a_dry_run_writes_nothing() {
  machine
  echo 'KERNEL_CMDLINE[default]+="rw"' >"$(DEFAULTS)"
  t_run boot --dry-run
  assert_status 0
  assert_eq 'KERNEL_CMDLINE[default]+="rw"' "$(cat "$(DEFAULTS)")"
}

test_unknown_bootloaders_are_refused() {
  machine
  t_run boot --yes
  assert_status 1
  assert_contains "$T_OUT" "no limine configuration found"
}

test_arguments() {
  t_run boot --bogus
  assert_status 2
  t_run boot --help
  assert_contains "$T_OUT" "usage: sudo setup-boot.sh"
}

t_main
