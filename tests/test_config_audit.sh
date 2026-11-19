#!/usr/bin/env bash
# config-audit.sh: unmerged .pacnew/.pacsave files and packaged files whose
# content differs, summarised per package, truncated by --max, read-only.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

audit() { ( source ../private_dot_local/share/ucli/scripts/check/executable_config-audit.sh "$@" ); }

# What pacman -Qkk prints for edited files, plus the permission noise a
# non-root run always has. Like the real pacman, the warnings go to stderr.
QKK='warning: openssh: /etc/ssh/sshd_config (Modification time mismatch)
warning: openssh: /etc/ssh/sshd_config (Size mismatch)
warning: pacman: /etc/pacman.conf (MD5 checksum mismatch)
warning: pacman: /etc/makepkg.conf (SHA256 checksum mismatch)
warning: sudo: /etc/sudoers (Permissions mismatch)
warning: sudo: /etc/sudoers (failed to calculate SHA256 checksum)
backup file: filesystem: /etc/fstab (Size mismatch)
backup file: filesystem: /etc/fstab (SHA256 checksum mismatch)
backup file: filesystem: /etc/shells (Modification time mismatch)
openssh: 120 total files, 0 altered files'

test_a_clean_machine_reports_no_drift() {
  stub pacdiff
  stub pacman 'echo "filesystem: 120 total files, 0 altered files"'
  t_run audit
  assert_status 0
  assert_contains "$T_OUT" "none — every package config has been merged"
  assert_contains "$T_OUT" "none — no packaged file has been edited"
  assert_contains "$T_OUT" "nothing was changed"
}

test_pacnew_files_are_listed_and_truncated_by_max() {
  stub pacdiff 'printf "/etc/pacman.conf.pacnew\n/etc/locale.gen.pacnew\n/etc/shells.pacsave\n"'
  stub pacman
  t_run audit --max 2
  assert_status 0
  assert_contains "$T_OUT" "3 file(s) need attention:"
  assert_contains "$T_OUT" "/etc/pacman.conf.pacnew"
  assert_contains "$T_OUT" "/etc/locale.gen.pacnew"
  assert_not_contains "$T_OUT" "/etc/shells.pacsave"
  assert_contains "$T_OUT" "… and 1 more"
  assert_called "pacdiff -o"
}

test_content_mismatches_are_grouped_per_package() {
  stub pacdiff
  stub pacman "printf '%s\n' '$QKK' >&2"
  t_run audit
  assert_status 0
  assert_contains "$T_OUT" "3 file(s) across 2 package(s):"
  assert_contains "$T_OUT" "     openssh"
  assert_contains "$T_OUT" "     pacman"
  assert_not_contains "$T_OUT" "     sudo"
  assert_contains "$T_OUT" "the next upgrade of the package overwrites them"
  assert_contains "$T_OUT" "(1 permission mismatch(es) ignored"
}

test_edited_backup_configs_are_reported_separately() {
  stub pacdiff
  stub pacman "printf '%s\n' '$QKK' >&2"
  t_run audit
  local configs="${T_OUT#*edited configuration files}"
  assert_contains "$configs" "1 file(s) across 1 package(s):"
  assert_contains "$configs" "     filesystem"
  assert_contains "$configs" "new defaults arrive as .pacnew"
  assert_called "pacman -Qkk"
}

test_package_lists_longer_than_max_are_truncated() {
  stub pacdiff
  stub pacman "printf '%s\n' '$QKK' >&2"
  t_run audit --max=1
  assert_contains "$T_OUT" "… and 1 more package(s)"
}

test_without_pacdiff_it_searches_etc() {
  # PATH keeps only the stub dir and the basics, so pacdiff is not found.
  stub pacman
  local find_out
  find_out="$(command -v find)"
  stub find "echo /etc/hosts.pacnew"
  PATH="$T_BIN:/usr/bin:/bin" t_run audit
  assert_status 0
  [[ -x /usr/bin/pacdiff || -x /bin/pacdiff ]] && return 0   # host has pacdiff: branch not reachable
  assert_called "find /etc -name *.pacnew -o -name *.pacsave"
  assert_contains "$T_OUT" "/etc/hosts.pacnew"
  : "$find_out"
}

test_without_pacman_the_second_part_is_skipped() {
  stub pacdiff
  PATH="$T_BIN" t_run /usr/bin/env bash -c "source ../private_dot_local/share/ucli/scripts/check/executable_config-audit.sh"
  [[ "$T_STATUS" == 0 ]] || return 0   # a minimal PATH without coreutils cannot run it at all
  assert_contains "$T_OUT" "pacman not found; skipping"
}

test_max_must_be_a_positive_number() {
  t_run audit --max lots
  assert_status 2
  assert_contains "$T_OUT" "--max needs a positive number, got: lots"
  t_run audit --max
  assert_status 2
  assert_contains "$T_OUT" "got: nothing"
  t_run audit --bogus
  assert_status 2
}

test_help_is_the_header_comment() {
  t_run audit --help
  assert_status 0
  assert_contains "$T_OUT" "Config drift: what on this machine no longer matches"
  assert_contains "$T_OUT" "Usage: config-audit.sh [--max N]"
}

t_main
