#!/usr/bin/env bash
# install-firefox-policies.sh: the extension lists become ExtensionSettings in
# /etc/firefox/policies/policies.json (and the Flatpak twin), merged into what
# is already there, atomically, never over invalid JSON. UCLI_ETC_ROOT roots
# every system path in the sandbox; only GUIDs with a known AMO slug are used,
# so nothing goes to the network.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

policies() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-firefox-policies.sh "$@" ); }

POLICY() { printf '%s' "$UCLI_ETC_ROOT/etc/firefox/policies/policies.json"; }
setting() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["policies"]["ExtensionSettings"][sys.argv[2]]["install_url"])' "$(POLICY)" "$1"; }

lists() {
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT" "$HOME/.config/ucli/firefox"
  printf '# the one add-on\nuBlock0@raymondhill.net\n\n' >"$HOME/.config/ucli/firefox/extensions.txt"
  printf 'react-devtools@mozilla.com\n' >"$HOME/.config/ucli/firefox/dev-extensions.txt"
}

test_the_shipped_list_becomes_a_policy() {
  lists
  t_run policies
  assert_status 0
  assert_contains "$T_OUT" "wrote $(POLICY)"
  assert_eq "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi" "$(setting uBlock0@raymondhill.net)"
  assert_contains "$(cat "$(POLICY)")" '"installation_mode": "normal_installed"'
}

test_personal_and_dev_lists_are_added_without_duplicates() {
  lists
  printf 'darkreader@darkreader.org\nuBlock0@raymondhill.net  # again\n' >"$HOME/.config/ucli/firefox/personal-extensions.txt"
  t_run policies --dev
  assert_contains "$T_OUT" "Firefox extensions: 3 configured"
  setting darkreader@darkreader.org >/dev/null || t_die "personal list not applied"
  setting react-devtools@mozilla.com >/dev/null || t_die "--dev list not applied"
}

test_other_policies_are_kept_and_a_rerun_is_a_no_op() {
  lists
  mkdir -p "$(dirname "$(POLICY)")"
  echo '{"policies": {"DisableTelemetry": true}}' >"$(POLICY)"
  policies >/dev/null
  assert_contains "$(cat "$(POLICY)")" '"DisableTelemetry": true'
  t_run policies
  assert_contains "$T_OUT" "policy already up to date"
}

test_an_invalid_policy_file_is_never_overwritten() {
  lists
  mkdir -p "$(dirname "$(POLICY)")"
  echo '{ not json' >"$(POLICY)"
  t_run policies
  assert_status 1
  assert_contains "$T_OUT" "is not valid JSON"
  assert_eq "{ not json" "$(cat "$(POLICY)")"
}

test_a_flatpak_firefox_gets_its_own_copy() {
  lists
  mkdir -p "$UCLI_ETC_ROOT/var/lib/flatpak/app/org.mozilla.firefox"
  t_run policies
  assert_status 0
  assert_file "$UCLI_ETC_ROOT/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json"
}

test_dry_run_writes_nothing() {
  lists
  t_run policies --dry-run
  assert_status 0
  assert_contains "$T_OUT" "== $(POLICY) (dry run, not written)"
  assert_contains "$T_OUT" '"install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"'
  assert_no_file "$(POLICY)"
}

test_user_takes_a_name() {
  lists
  t_run policies --user "$(id -un)" --dry-run
  assert_status 0
  assert_not_contains "$T_OUT" "unknown arg"
  t_run policies --user
  assert_status 2
  assert_contains "$T_OUT" "--user needs a name"
}

test_empty_lists_write_nothing() {
  lists
  : >"$HOME/.config/ucli/firefox/extensions.txt"
  t_run policies
  assert_status 0
  assert_contains "$T_OUT" "Nothing to write."
  assert_no_file "$(POLICY)"
}

t_main
