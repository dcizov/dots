# shellcheck shell=bash
# AUR lookups — one implementation, two callers.
#
# `install-packages.sh` resolves every package name through these, and
# `validate-packages.sh` checks the arrays against them. They each used to carry
# their own copy of the same embedded Python, which is exactly how the two drift
# apart later.
#
# Primary: the AUR RPC (fast, structured). Fallback: git ls-remote, which still
# works when the RPC is down or rate-limited.

aur_exists() {
  local pkg="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$pkg" <<'PY' >/dev/null 2>&1
import json, sys, urllib.parse, urllib.request
pkg = sys.argv[1]
url = "https://aur.archlinux.org/rpc/v5/info?" + urllib.parse.urlencode({"arg[]": pkg})
with urllib.request.urlopen(url, timeout=15) as response:
    data = json.load(response)
for result in data.get("results", []):
    if result.get("Name") == pkg:
        sys.exit(0)
sys.exit(1)
PY
    return $?
  fi
  if command -v git >/dev/null 2>&1; then
    git ls-remote "https://aur.archlinux.org/${pkg}.git" >/dev/null 2>&1
    return $?
  fi
  return 1
}

# The name you type is not always the AUR package name: kwi is packaged as
# kwi-git, which `provides=kwi`. Ask the RPC for providers before calling a
# package missing, and prefer a non-git name when several offer it.
aur_provides() {
  local pkg="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$pkg" <<'PY' 2>/dev/null || true
import json, sys, urllib.parse, urllib.request
pkg = sys.argv[1]
url = "https://aur.archlinux.org/rpc/v5/search?" + urllib.parse.urlencode({"arg[]": pkg, "by": "provides"})
with urllib.request.urlopen(url, timeout=15) as response:
    data = json.load(response)
providers = [r["Name"] for r in data.get("results", []) if pkg in (r.get("Provides") or [])]
providers.sort(key=lambda name: (name.endswith("-git"), name))
if providers:
    print(providers[0])
PY
}
