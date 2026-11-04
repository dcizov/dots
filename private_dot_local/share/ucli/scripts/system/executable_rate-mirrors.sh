#!/usr/bin/env bash
# rate-mirrors.sh — `ucli mirrors`: rank pacman mirrors and install the result.
#
# A port of CachyOS' cachyos-rate-mirrors (CachyOS/CachyOS-PKGBUILDS, GPL-2.0) to
# this repo's rules. What is kept:
#
#   * rate-mirrors as the engine, `arch` and `cachyos` as the repositories,
#   * an https-only protocol and a maximum mirror delay,
#   * a geoip entry country (so the first hop starts in the right place), with
#     the CN tweak from the original (China's mirrors are tested on their own),
#   * the ranking written over /etc/pacman.d/<repo>mirrorlist with a backup of
#     the previous file.
#
# What is deliberately different:
#
#   * it runs as your user, not as root. rate-mirrors refuses root for a reason,
#     and only the final `install` needs sudo.
#   * the four hardcoded RU mirrors CachyOS force-inserts are NOT copied. This
#     repo does not pin third-party mirrors on someone's machine.
#   * it uses the shared ucli UI layer (title, progress steps, summary box) and
#     takes a Snapper snapshot first when snapper is configured.
#   * reflector from [extra] is supported as a fallback engine.
#
# Usage:
#   ucli mirrors                 rank + show, then ask before writing
#   ucli mirrors --dry-run       rank and show, write nothing
#   ucli mirrors --country DE    skip the geoip lookup
#   ucli mirrors --no-geo        let rate-mirrors start from its own default
#   ucli mirrors --yes           write without asking (scripts, first boot)
#   ucli mirrors --tool reflector
#   ucli mirrors --repos arch    only /etc/pacman.d/mirrorlist
#
# Options:
#   --dry-run              rank and print, change no file
#   --country CC           entry country for the ranking
#   --no-geo               do not look the country up (geoip.kde.org)
#   --protocol http|https  default https
#   --max-delay SECONDS    ignore mirrors whose sync is older (default 21600)
#   --max-mirrors N        mirrors to keep per repo (default 20)
#   --repos LIST           arch,cachyos (default: what this system actually has)
#   --tool NAME            auto|rate-mirrors|reflector (default auto)
#   --install              install the engine from the repos without asking
#   --yes                  no confirmation before writing
#   --no-snapshot          skip the restore point (also UCLI_NO_SNAPSHOT=1)
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

dry_run=0
assume_yes=0
take_snapshot=1
use_geo=1
country=""
protocol="https"
max_delay=21600
max_mirrors=20
repos_arg=""
tool="auto"
install_tool=0

while (($#)); do
  case "$1" in
    --dry-run|-n) dry_run=1 ;;
    --yes|-y) assume_yes=1 ;;
    --no-snapshot) take_snapshot=0 ;;
    --no-geo) use_geo=0 ;;
    --country) country="${2:-}"; use_geo=0; shift ;;
    --country=*) country="${1#*=}"; use_geo=0 ;;
    --protocol) protocol="${2:-}"; shift ;;
    --protocol=*) protocol="${1#*=}" ;;
    --max-delay) max_delay="${2:-}"; shift ;;
    --max-delay=*) max_delay="${1#*=}" ;;
    --max-mirrors) max_mirrors="${2:-}"; shift ;;
    --max-mirrors=*) max_mirrors="${1#*=}" ;;
    --repos) repos_arg="${2:-}"; shift ;;
    --repos=*) repos_arg="${1#*=}" ;;
    --tool) tool="${2:-}"; shift ;;
    --tool=*) tool="${1#*=}" ;;
    --install) install_tool=1 ;;
    -h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' \
                 "${BASH_SOURCE[0]}"; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

[[ "${UCLI_NO_SNAPSHOT:-0}" == 1 ]] && take_snapshot=0

# rate-mirrors refuses to run as root and sudo is only needed for the final
# install, so root is the wrong way to invoke this.
if (( EUID == 0 )); then
  printf 'run this as your user, not as root: it ranks unprivileged and calls sudo only to install the file\n' >&2
  exit 1
fi

case "$protocol" in
  http|https) ;;
  *) printf 'unsupported protocol: %s (http or https)\n' "$protocol" >&2; exit 2 ;;
esac
[[ "$max_delay" =~ ^[0-9]+$ ]] || { printf '--max-delay takes seconds\n' >&2; exit 2; }
[[ "$max_mirrors" =~ ^[0-9]+$ ]] || { printf '--max-mirrors takes a number\n' >&2; exit 2; }

# --- repositories -----------------------------------------------------------
# Arch first, then CachyOS when its mirrorlist is there. Each entry is
# "<rate-mirrors target>:<file>".
repo_target() {
  case "$1" in
    arch)    printf 'arch' ;;
    cachyos) printf 'cachyos' ;;
    *)       return 1 ;;
  esac
}

# UCLI_MIRRORLIST_DIR exists so a dry run (and the repo's own tests) can point at
# a scratch directory instead of /etc/pacman.d. It never changes in practice.
mirror_dir="${UCLI_MIRRORLIST_DIR:-/etc/pacman.d}"

repo_file() {
  case "$1" in
    arch)    printf '%s/mirrorlist' "$mirror_dir" ;;
    cachyos) printf '%s/cachyos-mirrorlist' "$mirror_dir" ;;
    *)       return 1 ;;
  esac
}

repos=()
if [[ -n "$repos_arg" ]]; then
  IFS=',' read -r -a repos <<<"${repos_arg// /}"
else
  [[ -f "$(repo_file arch)" ]] && repos+=(arch)
  [[ -f "$(repo_file cachyos)" ]] && repos+=(cachyos)
fi

if ((${#repos[@]} == 0)); then
  printf 'no mirrorlist found in %s (mirrorlist for Arch, cachyos-mirrorlist for CachyOS)\n' "$mirror_dir" >&2
  exit 1
fi
for r in "${repos[@]}"; do
  if ! file="$(repo_file "$r")"; then
    printf 'unknown repo: %s (arch, cachyos)\n' "$r" >&2
    exit 2
  fi
  [[ -f "$file" ]] || { printf 'missing %s for repo %s\n' "$file" "$r" >&2; exit 1; }
done

# --- engine -----------------------------------------------------------------
case "$tool" in
  auto|rate-mirrors|reflector) ;;
  *) printf 'unknown --tool: %s (auto, rate-mirrors, reflector)\n' "$tool" >&2; exit 2 ;;
esac

pick_tool() {
  case "$tool" in
    rate-mirrors|reflector) printf '%s' "$tool" ;;
    auto)
      if command -v rate-mirrors >/dev/null 2>&1; then
        printf 'rate-mirrors'
      elif command -v reflector >/dev/null 2>&1; then
        printf 'reflector'
      fi
      ;;
  esac
}

engine="$(pick_tool)"

if [[ -z "$engine" ]]; then
  # rate-mirrors is in [extra] since 2026, so this needs no AUR helper at all.
  printf 'neither rate-mirrors nor reflector is installed\n' >&2
  if (( install_tool )) || ui_confirm "Install rate-mirrors from the repos?"; then
    sudo pacman -S --needed --noconfirm rate-mirrors
    engine="rate-mirrors"
  else
    printf 'nothing to do: sudo pacman -S rate-mirrors   (or reflector)\n' >&2
    exit 1
  fi
fi

# --- entry country ----------------------------------------------------------
# Ported from cachyos-rate-mirrors: a nearby entry country makes the first hop
# sensible, which matters most where a country is partly blocked. Soft-fail on
# purpose — a ranking without it is still a ranking.
if [[ -z "$country" ]] && (( use_geo )); then
  if ui_have curl; then
    country="$(curl -fsS --connect-timeout 8 'https://geoip.kde.org/v1/ubiquity' 2>/dev/null \
      | sed -n 's:.*<CountryCode>\([A-Z][A-Z]\)</CountryCode>.*:\1:p' | head -n1 || true)"
  fi
fi

ui_title "Rank the fastest mirrors"
echo
ui_note "engine:   $engine"
ui_note "protocol: $protocol"
ui_note "repos:    ${repos[*]}"
ui_note "country:  ${country:-not set (engine default)}"
ui_note "max sync delay: ${max_delay}s · mirrors kept: ${max_mirrors}"
echo

if (( dry_run )); then
  ui_note "dry run: nothing will be written"
  echo
fi

# --- snapshot ---------------------------------------------------------------
if (( take_snapshot )) && [[ -x "$script_dir/snapshot-fresh-install.sh" ]]; then
  sudo "$script_dir/snapshot-fresh-install.sh" "ucli mirrors: before ranking" || true
fi

# --- ranking ----------------------------------------------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT

# The command is built as a string, not a function call: `gum spin` forks, and
# shell functions do not survive that (same reason install-dev-profile.sh keeps
# its steps as strings).
rank_command() { # rank_command <repo> <outfile>
  local repo="$1" out="$2" entry=""
  local target
  target="$(repo_target "$repo")"
  local -a geo=()
  if [[ -n "$country" ]]; then
    case "$engine" in
      rate-mirrors) geo=(--entry-country="$country") ;;
      reflector)    geo=(--country "$country") ;;
    esac
  fi

  local cmd
  case "$engine" in
    rate-mirrors)
      # RATE_MIRRORS_* is how the CachyOS script tunes the tool: --max-delay is
      # a per-subcommand flag there, the environment variable is the stable way
      # to reach it for every target.
      cmd="RATE_MIRRORS_MAX_DELAY=$max_delay RATE_MIRRORS_PROTOCOL=$protocol"
      cmd+=" RATE_MIRRORS_FETCH_MIRRORS_TIMEOUT=${RATE_MIRRORS_FETCH_MIRRORS_TIMEOUT:-30000}"
      # China keeps to its own mirrors in the original script: no neighbours, more
      # of the country tested. Unknown environment variables are ignored by
      # rate-mirrors, so this stays correct if the flags move again.
      if [[ "$country" == CN ]]; then
        cmd+=" RATE_MIRRORS_COUNTRY_NEIGHBORS_PER_COUNTRY=0"
        cmd+=" RATE_MIRRORS_COUNTRY_TEST_MIRRORS_PER_COUNTRY=50"
      fi
      cmd+=" rate-mirrors --save $(printf '%q' "$out")"
      cmd+=" --protocol=$protocol"
      for entry in "${geo[@]}"; do cmd+=" $(printf '%q' "$entry")"; done
      cmd+=" --max-mirrors-to-output=$max_mirrors $(printf '%q' "$target")"
      ;;
    reflector)
      cmd="reflector --protocol $protocol"
      local g
      for g in "${geo[@]}"; do cmd+=" $(printf '%q' "$g")"; done
      cmd+=" --latest $max_mirrors --sort rate --save $(printf '%q' "$out")"
      ;;
  esac

  # A ranked list with no Server line is a failure, not a result.
  printf '%s && [ -s %s ] && grep -q %s %s' \
    "$cmd" "$(printf '%q' "$out")" "'^Server'" "$(printf '%q' "$out")"
}

failed=()
ranked=()
i=0
total=${#repos[@]}
for repo in "${repos[@]}"; do
  out="$tmpdir/$repo.mirrorlist"
  step_cmd="$(rank_command "$repo" "$out")"
  if ui_step "$i" "$total" "$repo: ranking mirrors" -- bash -c "$step_cmd"; then
    ranked+=("$repo")
  else
    failed+=("$repo")
  fi
  i=$(( i + 1 ))
done

if ((${#ranked[@]} == 0)); then
  ui_fail "no mirrorlist was produced; the existing files are untouched"
  printf '  Retry, or fall back to the stock list: sudo pacman -Syu pacman-mirrorlist\n' >&2
  exit 1
fi

# --- what came out ----------------------------------------------------------
echo
for repo in "${ranked[@]}"; do
  out="$tmpdir/$repo.mirrorlist"
  n="$(grep -c '^Server' "$out" || true)"
  top="$(grep -m3 '^Server' "$out" | sed 's/^Server[[:space:]]*=[[:space:]]*//' || true)"
  ui_rule "$repo: $n mirrors"
  printf '%s\n' "$top" | while IFS= read -r line; do
    [[ -n "$line" ]] && ui_note "$line"
  done
done
echo

if (( dry_run )); then
  ui_box "Dry run: ${#ranked[@]} mirrorlist(s) ranked, nothing written."
  exit 0
fi

if (( ! assume_yes )); then
  ui_confirm "Write these over /etc/pacman.d (previous file kept as <name>.bak)?" \
    || { printf '\nnothing written.\n'; exit 0; }
fi

# --- write ------------------------------------------------------------------
written=()
for repo in "${ranked[@]}"; do
  out="$tmpdir/$repo.mirrorlist"
  dest="$(repo_file "$repo")"
  if sudo install -m 0644 --backup=simple --suffix=".bak" "$out" "$dest"; then
    written+=("$dest")
    ui_ok "$dest"
  else
    ui_fail "$dest"
  fi
done

echo
if ((${#failed[@]})); then
  ui_box "Wrote ${#written[@]} of ${total} mirrorlist(s). Failed: ${failed[*]}. Re-run 'ucli mirrors' to retry."
  exit 1
fi

ui_box "Done. ${#written[@]} mirrorlist(s) ranked.
The previous files are next to them as *.bak.
No refresh needed: pacman reads the list on its next run."
