#!/usr/bin/env bash
set -euo pipefail

# pacman's own output: colour, and the candy progress bar.
#
# Both are one commented line in /etc/pacman.conf that nothing uncomments for you:
#
#   #Color          →  Color        coloured pacman output
#   #ILoveCandy     →  ILoveCandy   the `-.-.-` progress bar
#
# Why this is a script and not a sed one-liner: the file belongs to pacman, so the
# edit has to respect its shape. The options have to live in the [options] section
# (a stray `Color` under a repository section is a parse error), the change has to
# be idempotent, the file gets a timestamped backup, and the result is validated
# with `pacman-conf --config` *before* it replaces the original — if it does not
# parse, the backup is kept and the original is left alone.
#
# Runs from `ucli setup-system` (right after the base packages, so the desktop
# install is already coloured) and on its own as `ucli setup-pacman`.
#
#   sudo ucli setup-pacman               apply
#   sudo ucli setup-pacman --dry-run     print the diff, write nothing
#   sudo ucli setup-pacman --status      report the two lines, write nothing
#
# Testable without root over /etc: UCLI_ETC_ROOT=/some/dir makes every path
# relative to that directory — the same seam setup-boot.sh uses.

dry_run=0
status=0
usage() {
  cat <<'USAGE'
usage: sudo setup-pacman.sh [--dry-run] [--status]

Uncomment `Color` and add `ILoveCandy` in the [options] section of
/etc/pacman.conf. Keeps a timestamped backup and validates the result with
pacman-conf before keeping it.

  --dry-run   print the diff, write nothing
  --status    print whether the two options are set, write nothing
USAGE
}
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    --status) status=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

# Test seam: prefix for every system path (/etc). Empty on a real machine.
etc_root="${UCLI_ETC_ROOT:-}"
conf="$etc_root/etc/pacman.conf"

if [[ "${EUID:-$(id -u)}" -ne 0 && -z "$etc_root" ]]; then
  echo "Run as root: sudo ucli setup-pacman" >&2
  exit 1
fi
if [[ ! -f "$conf" ]]; then
  echo "no $conf — this is not an Arch-family machine" >&2
  exit 1
fi

# set | commented out | missing — what the file says about one option right now.
state_of() {
  local opt="$1"
  if grep -qE "^[[:space:]]*${opt}[[:space:]]*\$" "$conf"; then
    printf 'set\n'
  elif grep -qE "^[[:space:]]*#[[:space:]]*${opt}[[:space:]]*\$" "$conf"; then
    printf 'commented out\n'
  else
    printf 'missing\n'
  fi
}

options=(Color ILoveCandy)
report() {
  local opt
  for opt in "${options[@]}"; do
    printf '  %-12s %s\n' "$opt:" "$(state_of "$opt")"
  done
}

if (( status )); then
  echo "pacman.conf: $conf"
  report
  if [[ "$(state_of Color)" == set && "$(state_of ILoveCandy)" == set ]]; then
    echo "nothing to do."
  else
    echo "apply with: sudo ucli setup-pacman"
  fi
  exit 0
fi

if [[ "$(state_of Color)" == set && "$(state_of ILoveCandy)" == set ]]; then
  echo "already set: Color and ILoveCandy are uncommented in $conf"
  exit 0
fi

# Rewrite into a temp file next to the original: uncomment each option inside
# [options], and insert the ones that are not there at all at the end of that
# section. Nothing outside [options] is touched, which is what keeps pacman's
# parser happy.
tmp="$(mktemp "$(dirname "$conf")/.pacman.conf.XXXXXX")"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

rc=0
awk -v opts="Color ILoveCandy" '
  BEGIN { n = split(opts, want, " ") }
  { line[NR] = $0 }
  END {
    start = 0
    for (i = 1; i <= NR; i++)
      if (line[i] ~ /^\[options\][[:space:]]*$/) { start = i; break }
    if (!start) exit 3

    stop = NR + 1
    for (i = start + 1; i <= NR; i++)
      if (line[i] ~ /^\[[^]]*\][[:space:]]*$/) { stop = i; break }

    icount = 0
    for (w = 1; w <= n; w++) {
      opt = want[w]
      done_already = 0
      for (i = start + 1; i < stop; i++)
        if (line[i] ~ ("^[[:space:]]*" opt "[[:space:]]*$")) { done_already = 1; break }
      if (done_already) continue

      for (i = start + 1; i < stop; i++) {
        if (line[i] ~ ("^[[:space:]]*#[[:space:]]*" opt "[[:space:]]*$")) {
          sub(/#[[:space:]]*/, "", line[i])
          done_already = 1
          break
        }
      }
      if (!done_already) insert[++icount] = opt
    }

    # New options go in after the last real line of [options], not after its
    # trailing blank lines — otherwise they read as part of the next section.
    ins = stop - 1
    while (ins > start && line[ins] ~ /^[[:space:]]*$/) ins--

    for (i = 1; i <= NR; i++) {
      print line[i]
      if (i == ins)
        for (j = 1; j <= icount; j++) print insert[j]
    }
  }
' "$conf" > "$tmp" || rc=$?

if (( rc != 0 )); then
  echo "could not rewrite $conf (no [options] section?) — nothing changed" >&2
  exit 1
fi

if cmp -s "$conf" "$tmp"; then
  echo "nothing to change in $conf"
  exit 0
fi

if command -v diff >/dev/null 2>&1; then
  diff -u --label "$conf (current)" --label "$conf (new)" "$conf" "$tmp" || true
fi

if (( dry_run )); then
  echo "dry-run: nothing written"
  exit 0
fi

# pacman's own parser is the referee. An unparsable file would break every later
# `pacman -S`, so this runs before the original is replaced.
if command -v pacman-conf >/dev/null 2>&1; then
  if ! pacman-conf --config "$tmp" >/dev/null 2>&1; then
    echo "the rewritten file does not parse with pacman-conf — nothing written" >&2
    pacman-conf --config "$tmp" >&2 || true
    exit 1
  fi
fi

backup="$conf.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$conf" "$backup"
# cat into the original file, not mv: keeps its owner, mode and inode.
cat "$tmp" > "$conf"

# Verify the edit landed, and put the backup back if it did not.
missing=0
for opt in "${options[@]}"; do
  [[ "$(state_of "$opt")" == set ]] || { echo "warning: $opt is still not set" >&2; missing=1; }
done
if (( missing )); then
  cp -p "$backup" "$conf"
  echo "restored $conf from $backup" >&2
  exit 1
fi

echo "pacman.conf: Color and ILoveCandy are set (backup: $backup)"
echo "the next pacman run is coloured, with the candy progress bar."
