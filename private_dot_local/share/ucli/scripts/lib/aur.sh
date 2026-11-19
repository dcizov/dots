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

# aur_build <pkg> <yes 0|1> [pgp-key] — clone https://aur.archlinux.org/<pkg>
# into a private temp dir and `makepkg -si` it, as the current (non-root) user.
# The key, when given, is imported first so makepkg can check the source
# signature the PKGBUILD lists in validpgpkeys; checksums are checked either
# way. (An AUR checkout carries no .sig file of its own — looking for one, as
# the paru and shelly installers each used to, always came up empty.) Git and
# gpg chatter goes to stderr: callers keep stdout for their one-line answer.
aur_build() {
  local pkg="$1" yes="${2:-0}" key="${3:-}" workdir
  workdir="$(mktemp -d -t "$pkg-build.XXXXXX")"
  (
    trap 'rm -rf "$workdir"' EXIT
    echo "cloning the $pkg AUR repository ..." >&2
    git clone -q "https://aur.archlinux.org/$pkg.git" "$workdir/$pkg" >&2
    cd "$workdir/$pkg" || exit 1
    if [[ -n "$key" ]] && command -v gpg >/dev/null 2>&1 && ! gpg --list-keys "$key" >/dev/null 2>&1; then
      gpg --recv-keys "$key" >&2 2>/dev/null \
        || gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key" >&2 2>/dev/null \
        || echo "warning: could not import PGP key $key; makepkg will refuse a signed source it cannot verify" >&2
    fi
    if (( yes )); then makepkg -si --noconfirm >&2; else makepkg -si >&2; fi
  )
}
