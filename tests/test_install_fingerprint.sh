#!/usr/bin/env bash
# install-fingerprint.sh: reader detection, fprintd install + service, status,
# and above all the --pam edit of system-auth, which must never be able to
# lock anyone out.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

fingerprint() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-fingerprint.sh "$@" ); }

# Arch's stock /etc/pam.d/system-auth (pambase), the file --pam edits.
ARCH_SYSTEM_AUTH='#%PAM-1.0

auth       required                    pam_faillock.so      preauth
# Optionally use requisite above if you do not want to prompt for the password
# on locked accounts.
-auth      [success=2 default=ignore]  pam_systemd_home.so
auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok
auth       [default=die]               pam_faillock.so      authfail
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so      authsucc

-account   [success=1 default=ignore]  pam_systemd_home.so
account    required                    pam_unix.so
account    optional                    pam_permit.so
account    required                    pam_time.so'

machine() {
  export UCLI_ETC_ROOT="$T_ROOT/root" USER=alice
  mkdir -p "$UCLI_ETC_ROOT/etc/pam.d"
  printf '%s\n' "$ARCH_SYSTEM_AUTH" >"$UCLI_ETC_ROOT/etc/pam.d/system-auth"
  stub sudo '"$@"'
  stub pacman
  stub systemctl
  stub lsusb 'echo "Bus 003 Device 004: ID 27c6:6594 Shenzhen Goodix Fingerprint"'
}
PAM() { printf '%s' "$UCLI_ETC_ROOT/etc/pam.d/system-auth"; }

test_pam_goes_above_every_auth_line_so_no_jump_moves() {
  machine
  t_run fingerprint --pam --yes
  assert_status 0
  local first_auth
  first_auth="$(grep -nE '^-?auth' "$(PAM)" | head -1)"
  assert_contains "$first_auth" "pam_fprintd.so"
  # Every [success=N] jump in the auth stack must land where it did before:
  # nothing may have been inserted between a jump and its target.
  awk '/^-?auth/ { n++; line[n] = $0 }
       END { for (i = 1; i <= n; i++) if (match(line[i], /success=[0-9]+/)) {
               k = substr(line[i], RSTART + 8, RLENGTH - 8) + 0
               for (j = i + 1; j <= i + k; j++) if (line[j] ~ /pam_fprintd/) { print "jump crosses fprintd: " line[i]; exit 1 } } }' "$(PAM)" \
    || t_die "a [success=N] jump now skips pam_fprintd instead of its old target"
  # and the original lines are all still there, in order
  assert_eq "$(printf '%s\n' "$ARCH_SYSTEM_AUTH")" "$(grep -v pam_fprintd "$(PAM)")"
  assert_file "$(PAM).ucli-backup"
}

test_pam_is_idempotent_and_refuses_an_unknown_file() {
  machine
  fingerprint --pam --yes >/dev/null 2>&1
  t_run fingerprint --pam --yes
  assert_contains "$T_OUT" "pam_fprintd already present"
  assert_eq 1 "$(grep -c pam_fprintd "$(PAM)")"
  printf 'auth required pam_deny.so\n' >"$(PAM)"
  rm -f "$(PAM).ucli-backup"
  t_run fingerprint --pam --yes
  assert_status 1
  assert_contains "$T_OUT" "no 'auth ... pam_unix.so' line found"
  assert_eq "auth required pam_deny.so" "$(cat "$(PAM)")"
}

test_without_pam_the_file_is_not_touched() {
  machine
  t_run fingerprint --yes
  assert_status 0
  assert_called "pacman -S --needed --noconfirm fprintd"
  assert_called "systemctl enable --now fprintd.service"
  assert_eq "$(printf '%s\n' "$ARCH_SYSTEM_AUTH")" "$(cat "$(PAM)")"
  assert_contains "$T_OUT" "the finger enrolled here is alice's"
}

test_no_reader_installs_nothing_unless_forced() {
  machine
  stub lsusb 'echo "Bus 001 Device 002: ID 046d:c52b Logitech Receiver"'
  t_run fingerprint --yes
  assert_status 0
  assert_contains "$T_OUT" "No fingerprint reader found"
  assert_not_called "pacman -S"
  t_run fingerprint --yes --force
  assert_contains "$T_OUT" "not detected, continuing (--force)"
  assert_called "pacman -S --needed --noconfirm fprintd"
}

test_an_installed_fprintd_is_not_reinstalled() {
  machine; stub fprintd
  t_run fingerprint --yes
  assert_contains "$T_OUT" "fprintd: already installed"
  assert_not_called "pacman -S"
}

test_status_reports_reader_service_fingers_and_pam() {
  machine; stub fprintd
  stub fprintd-list 'printf "Fingerprints for user alice on Goodix:\n - #0: right-index-finger\n"'
  stub systemctl 'echo active'
  t_run fingerprint --status
  assert_status 0
  assert_contains "$T_OUT" "reader      : found"
  assert_contains "$T_OUT" "service     : active"
  assert_contains "$T_OUT" "enrolled    : right-index-finger"
  assert_contains "$T_OUT" "PAM (system-auth): not wired (--pam)"
}

test_enroll_needs_fprintd() {
  machine
  t_run fingerprint --enroll
  assert_status 1
  assert_contains "$T_OUT" "fprintd is not installed"
}

test_arguments() {
  t_run fingerprint --bogus
  assert_status 2
  t_run fingerprint --help
  assert_contains "$T_OUT" "Usage: install-fingerprint.sh"
}

t_main
