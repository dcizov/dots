#!/usr/bin/env bash
set -uo pipefail

# Install Firefox extensions the way Firefox is meant to be configured: an
# enterprise policy file, not files dropped into a profile.
#
# Why policies and not the four alternatives:
#
#   -install-global-extension <xpi>   removed in Gecko 1.9.2 (Firefox 3.6). Gone.
#   -install-addon / -install-addon-from-file
#                                     still exist, but they are per-launch,
#                                     interactive-ish, and the resulting add-on is
#                                     a normal profile install; a shortcut that
#                                     has to run before every start is not a
#                                     configuration.
#   <profile>/extensions/<id>.xpi     what this repo did before. It works only
#                                     because user.js lowered
#                                     extensions.autoDisableScopes to 14 so
#                                     "foreign installs" in the profile scope are
#                                     imported enabled; it needs a profile to
#                                     exist (so Firefox must have been launched
#                                     once), it is invisible in about:policies,
#                                     and Firefox only scans on startup.
#   policies.json                     Mozilla's supported unattended path: one
#                                     file, no profile needed, applied on the
#                                     next start, extensions installed *and*
#                                     enabled, visible in about:policies, and it
#                                     survives a profile reset.
#
# Location (Firefox Admin Docs, "Configuring policies"): on Linux either
# <install dir>/distribution/policies.json or /etc/firefox/policies/policies.json.
# Arch's firefox puts the install directory in /usr/lib/firefox, which belongs to
# the package, so /etc is the one that is ours. Flatpak's Firefox cannot read the
# host /etc and reads the same file from an extension directory instead; both are
# written when a Flatpak install is present.
#
# installation_mode is `normal_installed`, not `force_installed`: the extension is
# installed automatically and enabled, but you can still disable or remove it in
# about:addons (force_installed greys that out). If it is removed, the next start
# puts it back, because the policy still says it belongs here — delete the line in
# ~/.config/ucli/firefox/extensions.txt to make it stay gone.
#
# Usage:
#   sudo install-firefox-policies.sh [--dev] [--dry-run] [--user NAME]

dev_list=0
dry_run=0
target_user="${SUDO_USER:-$USER}"
usage() {
  cat <<'USAGE'
usage: sudo install-firefox-policies.sh [--dev] [--dry-run] [--user NAME]

Writes /etc/firefox/policies/policies.json (and the Flatpak equivalent) so the
extensions in ~/.config/ucli/firefox/{extensions,personal-extensions}.txt are
installed and enabled on the next Firefox start.

  --dev           add ~/.config/ucli/firefox/dev-extensions.txt too
  --dry-run       show the policy, write nothing
  --user NAME     whose extension lists to read (default: $SUDO_USER, else $USER)
USAGE
}
for arg in "$@"; do
  case "$arg" in
    --dev) dev_list=1 ;;
    --dry-run|-n) dry_run=1 ;;
    --user) shift; target_user="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

# Test seam: prefix for every system path, so the whole thing can be exercised
# against a fake tree.
root="${UCLI_ETC_ROOT:-}"
if [[ -n "$root" ]]; then
  real_home="${HOME:-}"
else
  real_home="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "$real_home" ]] || real_home="${HOME:-}"
fi
if [[ -z "$real_home" ]]; then
  echo "error: cannot resolve the home directory of $target_user" >&2
  exit 1
fi
if [[ "${EUID:-$(id -u)}" -ne 0 && -z "$root" && "$dry_run" -eq 0 ]]; then
  echo "Run as root: sudo ucli firefox-policies" >&2
  echo "  (or: sudo $0$([[ $dev_list == 1 ]] && echo ' --dev'))" >&2
  exit 1
fi

fx_dir="$real_home/.config/ucli/firefox"
lists=("$fx_dir/extensions.txt")
[[ -r "$fx_dir/personal-extensions.txt" ]] && lists+=("$fx_dir/personal-extensions.txt")
(( dev_list )) && lists+=("$fx_dir/dev-extensions.txt")

ids=()
for list in "${lists[@]}"; do
  [[ -r "$list" ]] || continue
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    dup=0
    for seen in ${ids[@]+"${ids[@]}"}; do [[ "$seen" == "$line" ]] && dup=1; done
    (( dup )) || ids+=("$line")
  done <"$list"
done

if ((${#ids[@]} == 0)); then
  # The repo ships one extension (uBlock Origin) in extensions.txt, so reaching
  # this point means both lists are empty: the line was deleted, or this is a
  # machine where only the personal file exists and is blank.
  echo "no Firefox extensions configured (${fx_dir}/extensions.txt has no entries"
  echo "and there is no personal-extensions.txt). Nothing to write."
  exit 0
fi
echo "Firefox extensions: ${#ids[@]} configured"

# Known AMO slugs. Anything else is looked up through the addons.mozilla.org API
# (single request per unknown ID), so a list is not limited to this table.
declare -A KNOWN_SLUGS=(
  ["bitwarden-browser-extension@bitwarden.com"]="bitwarden-password-manager"
  ["darkreader@darkreader.org"]="darkreader"
  ["violentmonkey@violentmonkey.net"]="violentmonkey"
  ["react-devtools@mozilla.com"]="react-devtools"
  ["uBlock0@raymondhill.net"]="ublock-origin"
)

slug_for() {
  local guid="$1"
  if [[ -n "${KNOWN_SLUGS[$guid]:-}" ]]; then
    printf '%s\n' "${KNOWN_SLUGS[$guid]}"
    return 0
  fi
  python3 - "$guid" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

guid = sys.argv[1]
url = ("https://addons.mozilla.org/api/v5/addons/search/?"
       + urllib.parse.urlencode({"guid": guid, "app": "firefox",
                                 "type": "extension", "page_size": 1}))
request = urllib.request.Request(url, headers={"User-Agent": "ucli (Arch dotfiles)"})
try:
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
except Exception as error:  # network, DNS, JSON, rate limit
    print(f"lookup failed: {error}", file=sys.stderr)
    sys.exit(1)
results = payload.get("results") or []
if not results:
    print("no addon with that GUID on addons.mozilla.org", file=sys.stderr)
    sys.exit(1)
print(results[0]["slug"])
PY
}

entries=()
skipped=0
for guid in "${ids[@]}"; do
  slug="$(slug_for "$guid")" || {
    echo "warning: skipping $guid (no AMO slug)" >&2
    skipped=$((skipped + 1))
    continue
  }
  url="https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi"
  entries+=("$guid"$'\t'"$url")
  echo "  $guid -> $url"
done

if ((${#entries[@]} == 0)); then
  echo "error: no extension could be resolved to an AMO URL; nothing written" >&2
  exit 1
fi

# Merge into an existing policy file instead of replacing it: this file is shared
# with anything else that configures Firefox, and only our ExtensionSettings
# entries are ours to write. `*` is never set — that wildcard would block every
# other extension the user tries to install.
merge_policy() {
  local path="$1"
  local -a pairs=("${entries[@]}")
  python3 - "$path" "${pairs[@]}" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
pairs = [arg.split("\t", 1) for arg in sys.argv[2:]]

existing = {}
if path.exists():
    try:
        existing = json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as error:
        print(f"{path} is not valid JSON ({error}); refusing to overwrite it",
              file=sys.stderr)
        sys.exit(2)

policies = existing.setdefault("policies", {})
settings = policies.setdefault("ExtensionSettings", {})
for guid, url in pairs:
    settings[guid] = {
        "installation_mode": "normal_installed",
        "install_url": url,
    }

rendered = json.dumps(existing, indent=2) + "\n"
if path.exists() and path.read_text() == rendered:
    print("unchanged")
    sys.exit(0)

# Atomic: a half-written policy file makes Firefox ignore policies entirely.
path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".policies.", suffix=".json")
with os.fdopen(fd, "w") as handle:
    handle.write(rendered)
os.chmod(tmp, 0o644)
os.replace(tmp, path)
print("written")
PY
}

targets=("${root}/etc/firefox/policies/policies.json")

# Flatpak Firefox reads policies from an extension directory, not from /etc.
flatpak_dirs=(
  "/var/lib/flatpak/app/org.mozilla.firefox"
  "$real_home/.local/share/flatpak/app/org.mozilla.firefox"
)
for app_dir in "${flatpak_dirs[@]}"; do
  [[ -d "${root}${app_dir}" ]] || continue
  for arch in x86_64 aarch64; do
    targets+=("${root}/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${arch}/stable/policies/policies.json")
  done
  break
done

rc=0
for target in "${targets[@]}"; do
  if (( dry_run )); then
    echo
    echo "== $target (dry run, not written)"
    python3 - "$target" "${entries[@]}" <<'PY'
import json
import sys

pairs = [arg.split("\t", 1) for arg in sys.argv[2:]]
print(json.dumps({"policies": {"ExtensionSettings": {
    guid: {"installation_mode": "normal_installed", "install_url": url}
    for guid, url in pairs}}}, indent=2))
PY
    continue
  fi
  result="$(merge_policy "$target")"
  case "$result" in
    written) echo "wrote $target" ;;
    unchanged) echo "$target: policy already up to date" ;;
    *)
      echo "error: could not update $target" >&2
      rc=1
      ;;
  esac
done

if (( rc == 0 )); then
  echo
  echo "Firefox applies this on the next start. Check it with about:policies"
  echo "(errors are listed at the top of that page)."
  (( skipped )) && echo "warning: $skipped extension(s) could not be resolved and were left out" >&2
  echo "To stop managing one: delete its line in $fx_dir/ and run this step again;"
  echo "it then stays installed but unmanaged — remove it in about:addons."
fi
exit "$rc"
