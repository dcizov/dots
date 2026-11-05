#!/usr/bin/env bash
# DNS for the connections NetworkManager already knows about:
#
#   ucli dns list                          connections, their servers, presets
#   ucli dns status                        the active connection in one line
#   ucli dns set cloudflare                a preset from DNS_PRESETS (packages.bash)
#   ucli dns set "1.1.1.1 9.9.9.9"         literal servers
#   ucli dns set cloudflare --dot          also ask for DNS-over-TLS (strict)
#   ucli dns reset                         back to what DHCP hands out
#
# Everything goes through nmcli, so it survives reboots and lives in the
# connection profile — no resolv.conf editing, no daemon of our own. Which
# connection is targeted: the active one, or --connection <name>.
#
# `set` also sets ipv4.ignore-auto-dns/ipv6.ignore-auto-dns, otherwise NM keeps
# prepending the DHCP servers and the preset is half-applied — the classic "I set
# 1.1.1.1 and it still resolves through the router" bug.
#
# DNS-over-TLS needs a NetworkManager DNS plugin that supports it
# (dns-systemd-resolved). The property is feature-detected, so on a machine whose
# NM cannot do it the script says so instead of writing a setting that does
# nothing.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

usage() {
  cat <<'USAGE'
usage: dns.sh list
       dns.sh status
       dns.sh set <preset|"ip ip ..."> [--connection NAME] [--dot] [--dry-run]
       dns.sh reset [--connection NAME] [--dry-run]

Presets come from DNS_PRESETS in packages.bash. --connection targets a specific
NetworkManager profile (default: the active one). --dot asks for DNS-over-TLS
when the NetworkManager DNS plugin supports it.
USAGE
}

action=""
value=""
connection=""
dot=0
dry_run=0
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --connection) connection="${2:-}"; shift 2 ;;
    --connection=*) connection="${1#*=}"; shift ;;
    --dot) dot=1; shift ;;
    --dry-run|-n) dry_run=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) if [[ -z "$action" ]]; then action="$1"; elif [[ -z "$value" ]]; then value="$1"; else
         echo "unexpected argument: $1" >&2; exit 2
       fi; shift ;;
  esac
done

if ! ui_have nmcli; then
  echo "nmcli not found — this step configures NetworkManager connections" >&2
  echo "install networkmanager, or set DNS in your desktop's network settings" >&2
  exit 1
fi

packages_bash="$real_home/.config/ucli/packages.bash"
if [[ -r "$packages_bash" ]]; then
  # shellcheck source=/dev/null
  . "$packages_bash"
fi
if ! declare -p DNS_PRESETS >/dev/null 2>&1; then
  DNS_PRESETS=()
fi

active_connection() {
  nmcli -t -f NAME connection show --active 2>/dev/null | head -1
}

target_connection() {
  if [[ -n "$connection" ]]; then
    printf '%s\n' "$connection"
    return 0
  fi
  local c
  c="$(active_connection)"
  if [[ -z "$c" ]]; then
    echo "no active NetworkManager connection; pass --connection <name>" >&2
    echo "  connections: nmcli -t -f NAME connection show" >&2
    return 1
  fi
  printf '%s\n' "$c"
}

current_dns() {
  local c="$1" v4 v6
  v4="$(nmcli -g ipv4.dns connection show "$c" 2>/dev/null | tr ',' ' ' | tr -d '\n' || true)"
  v6="$(nmcli -g ipv6.dns connection show "$c" 2>/dev/null | tr ',' ' ' | tr -d '\n' || true)"
  printf 'v4: %s\nv6: %s\n' "${v4:-—}" "${v6:-—}"
}

preset_match() {
  local c="$1" entry name v4 v6 cur4 cur6
  cur4="$(nmcli -g ipv4.dns connection show "$c" 2>/dev/null | tr ',' ' ' | tr -d '\n' || true)"
  for entry in "${DNS_PRESETS[@]}"; do
    IFS='|' read -r name v4 v6 <<<"$entry"
    if [[ "$(printf '%s' "$cur4" | tr -s ' ' | sed 's/^ *//;s/ *$//')" == "$v4" ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  # Unwrap the comma form nmcli prints for IPv4 lists as well.
  cur6="$(nmcli -g ipv6.dns connection show "$c" 2>/dev/null | tr ',' ' ' | tr -d '\n' || true)"
  for entry in "${DNS_PRESETS[@]}"; do
    IFS='|' read -r name v4 v6 <<<"$entry"
    if [[ "$cur4" == "$v4" && "$cur6" == "$v6" ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  printf 'custom\n'
}

list_dns() {
  ui_rule "connections"
  local c active
  active="$(active_connection)"
  while read -r c; do
    [[ -n "$c" ]] || continue
    local mark="  "
    if [[ "$c" == "$active" ]]; then mark="❯ "; fi
    local v4 v6
    v4="$(nmcli -g ipv4.dns connection show "$c" 2>/dev/null | tr ',' ' ' | tr -d '\n' || true)"
    v6="$(nmcli -g ipv6.dns connection show "$c" 2>/dev/null | tr ',' ' ' | tr -d '\n' || true)"
    printf '%s%-28s dns4=%-32s dns6=%s\n' "$mark" "$c" "${v4:-—}" "${v6:-—}"
  done < <(nmcli -t -f NAME connection show 2>/dev/null)

  echo
  ui_rule "presets (DNS_PRESETS in packages.bash)"
  local entry name v4 v6
  for entry in "${DNS_PRESETS[@]}"; do
    IFS='|' read -r name v4 v6 <<<"$entry"
    printf '  %-18s %-34s %s\n' "$name" "$v4" "$v6"
  done
  echo
  printf '  apply: sudo ucli dns set <preset>       revert: sudo ucli dns reset\n'
}

status_dns() {
  local c
  c="$(target_connection)" || exit 1
  ui_rule "dns: $c"
  current_dns "$c"
  printf 'preset: %s\n' "$(preset_match "$c")"
  printf 'dot:    %s\n' "$(nm_dot_state "$c")"
}

# Is DNS-over-TLS a property this NetworkManager knows, and what does it say?
nm_dot_state() {
  local c="$1" out
  if ! out="$(nmcli -f connection.dns-over-tls connection show "$c" 2>/dev/null)"; then
    printf 'unsupported by this NetworkManager/plugin\n'
    return 0
  fi
  out="$(printf '%s\n' "$out" | awk -F: 'NR==2 {print $2}' | tr -d ' ')"
  case "$out" in
    ""|"-1") printf 'default\n' ;;
    0) printf 'no\n' ;;
    1) printf 'opportunistic\n' ;;
    2) printf 'strict\n' ;;
    *) printf '%s\n' "$out" ;;
  esac
}

apply_dot() {
  local c="$1"
  if (( ! dot )); then
    return 0
  fi
  if ! nmcli -f connection.dns-over-tls connection show "$c" >/dev/null 2>&1; then
    echo "note: this NetworkManager has no connection.dns-over-tls property, so" >&2
    echo "      DNS-over-TLS was not requested. It needs the systemd-resolved DNS" >&2
    echo "      plugin; without it the servers above still work, unencrypted." >&2
    return 0
  fi
  if (( dry_run )); then
    printf '+ nmcli connection modify "%s" connection.dns-over-tls 2\n' "$c"
    return 0
  fi
  nmcli connection modify "$c" connection.dns-over-tls 2
  ui_ok "DNS-over-TLS: strict"
}

reactivate() {
  local c="$1"
  [[ "$(active_connection)" == "$c" ]] || { echo "  ($c is not the active connection; it applies when it connects)"; return 0; }
  if (( dry_run )); then
    printf '+ nmcli connection up "%s"\n' "$c"
    return 0
  fi
  nmcli connection up "$c" >/dev/null
  ui_ok "reconnected $c"
}

set_dns() {
  local want="$1" c entry name v4 v6
  c="$(target_connection)" || exit 1

  v4=""; v6=""
  for entry in "${DNS_PRESETS[@]}"; do
    IFS='|' read -r name v4 v6 <<<"$entry"
    [[ "$name" == "$want" ]] && break
    v4=""; v6=""
  done
  if [[ -z "$v4" ]]; then
    # Not a preset: accept a literal list of IPv4 addresses (IPv6 needs a preset
    # or --ipv6; nmcli itself would reject a mixed string).
    if [[ "$want" =~ ^[0-9.]+([[:space:],]+[0-9.]+)*$ ]]; then
      v4="${want//,/ }"
    else
      echo "no preset '$want'; presets:" >&2
      for entry in "${DNS_PRESETS[@]}"; do
        IFS='|' read -r name _ _ <<<"$entry"
        printf '  %s\n' "$name" >&2
      done
      return 2
    fi
  fi

  ui_rule "dns: $c ← ${want}"
  if (( dry_run )); then
    printf '+ nmcli connection modify "%s" ipv4.dns "%s" ipv4.ignore-auto-dns yes\n' "$c" "$v4"
    if [[ -n "$v6" ]]; then
      printf '+ nmcli connection modify "%s" ipv6.dns "%s" ipv6.ignore-auto-dns yes\n' "$c" "$v6"
    fi
  else
    nmcli connection modify "$c" ipv4.dns "$v4" ipv4.ignore-auto-dns yes
    if [[ -n "$v6" ]]; then
      nmcli connection modify "$c" ipv6.dns "$v6" ipv6.ignore-auto-dns yes
    fi
    ui_ok "ipv4.dns = $v4"
    [[ -n "$v6" ]] && ui_ok "ipv6.dns = $v6"
  fi
  apply_dot "$c"
  reactivate "$c"
}

reset_dns() {
  local c
  c="$(target_connection)" || exit 1
  ui_rule "dns: $c ← DHCP again"
  if (( dry_run )); then
    printf '+ nmcli connection modify "%s" ipv4.dns "" ipv4.ignore-auto-dns no ipv6.dns "" ipv6.ignore-auto-dns no\n' "$c"
    return 0
  fi
  nmcli connection modify "$c" ipv4.dns "" ipv4.ignore-auto-dns no \
                              ipv6.dns "" ipv6.ignore-auto-dns no
  ui_ok "back to the servers from DHCP/RA"
  reactivate "$c"
}

case "$action" in
  list|"") list_dns ;;
  status) status_dns ;;
  set)
    [[ -n "$value" ]] || { echo "usage: dns.sh set <preset|\"ip ip\">" >&2; exit 2; }
    set_dns "$value" ;;
  reset) reset_dns ;;
  *) usage; exit 2 ;;
esac
