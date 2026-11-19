#!/usr/bin/env bash
# dns.sh (`ucli dns`): presets from packages.bash or a literal IPv4 list onto a
# NetworkManager connection, IPv6 following the choice, reset to DHCP, DoT,
# and the status/list views. nmcli is a stateful fake over files in $NM.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

dns() { ( source ../private_dot_local/share/ucli/scripts/system/executable_dns.sh "$@" ); }

nm() {
  export NM="$T_ROOT/nm"
  mkdir -p "$NM"; : >"$NM/ipv4.dns"; : >"$NM/ipv6.dns"
  stub nmcli 'case "$*" in
    "-t -f NAME connection show --active") echo Home ;;
    "-t -f NAME connection show") printf "Home\nCafe\n" ;;
    "-g ipv4.dns connection show"*) cat "$NM/ipv4.dns" ;;
    "-g ipv6.dns connection show"*) cat "$NM/ipv6.dns" ;;
    "-f connection.dns-over-tls connection show"*) [[ ${FAKE_DOT:-1} == 1 ]] && printf "connection.dns-over-tls: %s\n" "$(cat "$NM/dot" 2>/dev/null || echo -1)" || exit 10 ;;
    "connection modify "*)
      set -- "${@:4}"
      while (($#)); do
        case $1 in ipv4.dns|ipv6.dns) printf "%s" "$2" >"$NM/$1" ;; connection.dns-over-tls) echo "$2" >"$NM/dot" ;; esac
        shift 2
      done ;;
    "connection up"*) ;;
  esac'
  t_config_file packages.bash <<'PKG'
DNS_PRESETS=(
  "cloudflare|1.1.1.1 1.0.0.1|2606:4700:4700::1111 2606:4700:4700::1001"
  "quad9|9.9.9.9 149.112.112.112|2620:fe::fe 2620:fe::9"
  "v4only|94.140.14.14 94.140.15.15|"
)
PKG
}

test_a_preset_sets_both_families_and_reconnects() {
  nm
  t_run dns set cloudflare
  assert_status 0
  assert_eq "1.1.1.1 1.0.0.1" "$(cat "$NM/ipv4.dns")"
  assert_eq "2606:4700:4700::1111 2606:4700:4700::1001" "$(cat "$NM/ipv6.dns")"
  assert_called "nmcli connection up Home"
}

test_an_ipv4_only_choice_clears_the_previous_ipv6_servers() {
  nm
  dns set cloudflare >/dev/null 2>&1
  t_run dns set "9.9.9.10, 149.112.112.10"
  assert_status 0
  assert_eq "9.9.9.10 149.112.112.10" "$(cat "$NM/ipv4.dns")"
  assert_eq "" "$(cat "$NM/ipv6.dns")" "cloudflare's IPv6 resolvers must not stay"
  dns set cloudflare >/dev/null 2>&1
  dns set v4only >/dev/null 2>&1
  assert_eq "" "$(cat "$NM/ipv6.dns")"
}

test_reset_status_and_list() {
  nm
  dns set quad9 >/dev/null 2>&1
  t_run dns status
  assert_contains "$T_OUT" "v4: 9.9.9.9 149.112.112.112"
  assert_contains "$T_OUT" "preset: quad9"
  t_run dns reset
  assert_eq "" "$(cat "$NM/ipv4.dns")"
  t_run dns list
  assert_contains "$T_PLAIN" "❯ Home"
  assert_contains "$T_OUT" "cloudflare"
}

test_dot_is_requested_only_when_supported() {
  nm
  t_run dns set quad9 --dot
  assert_eq 2 "$(cat "$NM/dot")"
  export FAKE_DOT=0
  rm "$NM/dot"
  t_run dns set quad9 --dot
  assert_contains "$T_OUT" "has no connection.dns-over-tls property"
  assert_no_file "$NM/dot"
}

test_dry_run_and_other_connections() {
  nm
  t_run dns set cloudflare --dry-run --connection Cafe
  assert_contains "$T_OUT" '+ nmcli connection modify "Cafe" ipv4.dns "1.1.1.1 1.0.0.1"'
  assert_contains "$T_OUT" "(Cafe is not the active connection"
  assert_eq "" "$(cat "$NM/ipv4.dns")"
}

test_errors() {
  nm
  t_run dns set nosuch
  assert_status 2
  assert_contains "$T_OUT" "no preset 'nosuch'; presets:"
  t_run dns set --connection
  assert_status 2
  assert_contains "$T_OUT" "--connection needs a name"
  t_run dns set
  assert_status 2
  rm "$T_BIN/nmcli"; t_minimal_path
  t_run dns list
  assert_status 1
  assert_contains "$T_OUT" "nmcli not found"
}

t_main
