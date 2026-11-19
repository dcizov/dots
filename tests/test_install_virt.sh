#!/usr/bin/env bash
# install-virt.sh (`ucli virt`): packages, a KVM warning when there is none,
# the libvirt group, the socket (or service) and the default NAT network.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

virt() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-virt.sh "$@" ); }

# host [member 0|1] [socket 0|1]
host() {
  export USER=alice UCLI_TEST_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_TEST_ROOT/dev"; : >"$UCLI_TEST_ROOT/dev/kvm"
  stub sudo '"$@"'; stub usermod; stub virsh 'echo "Active:         yes"'
  stub id "[[ \$1 == -nG ]] && { [[ ${1:-0} == 1 ]] && echo 'wheel libvirt' || echo wheel; }; exit 0"
  stub systemctl "case \$1 in cat) exit $((1 - ${2:-1})) ;; is-active) exit 0 ;; esac; exit 0"
  S="$(t_deployed install/install-virt)"
  t_fake_script "${S%/*}/install-packages.sh"
}

test_a_fresh_host_gets_packages_group_socket_and_network() {
  host 0 1
  t_run bash "$S" --yes
  assert_status 0
  assert_called "install-packages.sh --yes virt"
  assert_called "usermod -aG libvirt alice"
  assert_called "systemctl enable --now libvirtd.socket"
  assert_called "virsh -c qemu:///system net-start default"
  assert_called "virsh -c qemu:///system net-autostart default"
  assert_contains "$T_OUT" "default network: active"
  assert_not_contains "$T_OUT" "/dev/kvm is missing"
}

test_an_older_libvirt_gets_the_service_and_members_are_not_re_added() {
  host 1 0
  t_run bash "$S"
  assert_called "systemctl enable --now libvirtd.service"
  assert_not_called "usermod"
  assert_contains "$T_OUT" "alice already a member"
}

test_no_kvm_warns_and_no_service_skips_the_daemon() {
  host 1 1
  rm "$UCLI_TEST_ROOT/dev/kvm"
  t_run bash "$S" --no-service
  assert_status 0
  assert_contains "$T_OUT" "/dev/kvm is missing, so guests will run emulated"
  assert_not_called "systemctl enable"
  assert_not_called "virsh"
}

test_status_reports_without_changes() {
  host 0 1
  stub qemu-system-x86_64
  t_run virt --status
  assert_status 0
  assert_contains "$T_OUT" "qemu        : installed"
  assert_contains "$T_OUT" "virt-manager: MISSING"
  assert_contains "$T_OUT" "libvirt grp : no — run 'ucli virt'"
  assert_contains "$T_OUT" "daemon      : libvirtd.socket active"
  assert_not_called "usermod"
}

test_arguments() {
  t_run virt --bogus
  assert_status 2
}

t_main
