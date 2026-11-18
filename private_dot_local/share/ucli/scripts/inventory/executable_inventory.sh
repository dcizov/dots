#!/usr/bin/env bash
set -euo pipefail
umask 077
export LC_ALL=C

fail() { printf 'inventory: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
usage: inventory.sh [OUTPUT-DIR] [--appimage PATH ...]

Capture a private manifest as the desktop user. OUTPUT-DIR must not exist.
Defaults to ~/system-inventory/clean-<timestamp>. The home filesystem is
scanned for AppImages; pass --appimage for any additional directory or file.
This records AppImages and checksums, not copies of the binaries.
USAGE
}

out=""
image_paths=()
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --appimage)
      (($# >= 2)) || fail '--appimage needs a path'
      image_paths+=("$2")
      shift ;;
    -*) fail "unknown option: $1" ;;
    *) [[ -z "$out" ]] || fail 'give at most one output directory'; out="$1" ;;
  esac
  shift
done
(( EUID != 0 )) || fail 'run as the desktop user, not with sudo'
for cmd in pacman pacman-conf; do
  command -v "$cmd" >/dev/null || fail "$cmd is required"
done

out="${out:-$HOME/system-inventory/clean-$(date +%F-%H%M%S)}"
[[ ! -e "$out" && ! -L "$out" ]] || fail "output already exists: $out"
parent="$(dirname -- "$out")"
mkdir -p -- "$parent"
stage="$(mktemp -d -- "$parent/.inventory.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir -- "$stage"/{packages,flatpak,appimages}
{
  printf 'date: %s\n' "$(date -Iseconds)"
  printf 'host: %s\n' "$(uname -n)"
  printf 'user: %s\n' "$(id -un)"
} > "$stage/manifest.txt"

# Pacman -Q with a filter returns 1 for no matches. Accept that only when
# both streams are empty; a database/query error must not look like no packages.
query_filtered() {
  local dest="$1" status
  shift
  if pacman "$@" > "$dest" 2> "$stage/.pacman-stderr"; then
    cat "$stage/.pacman-stderr" >&2
  else
    status=$?
    if ((status != 1)) || [[ -s "$dest" || -s "$stage/.pacman-stderr" ]]; then
      cat "$stage/.pacman-stderr" >&2
      fail "pacman $* failed (exit $status)"
    fi
  fi
  rm -- "$stage/.pacman-stderr"
}
packages="$stage/packages"
pacman -Q > "$packages/all-installed-with-versions.txt"
pacman-conf --repo-list > "$packages/repositories.txt"
query_filtered "$packages/explicit-all-with-versions.txt" -Qe
query_filtered "$packages/pacman-explicit-native-with-versions.txt" -Qen
query_filtered "$packages/foreign-explicit-with-versions.txt" -Qem
query_filtered "$packages/foreign-all-with-versions.txt" -Qm
cut -d ' ' -f 1 "$packages/all-installed-with-versions.txt" > "$packages/all-installed.txt"
cut -d ' ' -f 1 "$packages/explicit-all-with-versions.txt" > "$packages/explicit-all.txt"
cut -d ' ' -f 1 "$packages/pacman-explicit-native-with-versions.txt" > "$packages/pacman-explicit-native.txt"
cut -d ' ' -f 1 "$packages/foreign-explicit-with-versions.txt" > "$packages/foreign-explicit.txt"
# Keep the legacy filenames for consumers of old inventories. "Foreign" does
# not imply that a package came from the AUR: it can be local or from an old repo.
cp -- "$packages/foreign-explicit.txt" "$packages/aur-explicit.txt"
cp -- "$packages/foreign-explicit-with-versions.txt" "$packages/aur-explicit-with-versions.txt"

flatpaks="$stage/flatpak"
flatpak_scope() {
  local scope="$1" option="$2"
  flatpak list "$option" --app --columns=ref,origin,active > "$flatpaks/$scope-refs.tsv" || fail "Flatpak app query failed for $scope"
  flatpak remotes "$option" --show-disabled --columns=name,url,collection,options > "$flatpaks/$scope-remotes.tsv" || fail "Flatpak remote query failed for $scope"
}
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
if command -v flatpak >/dev/null; then
  flatpak list --app --columns=application,name,branch,origin,installation > "$flatpaks/apps.tsv"
  flatpak list --app --columns=application > "$flatpaks/app-ids.txt"
  user_overrides="${FLATPAK_USER_DIR:-$data_home/flatpak}/overrides"
  system_overrides="${FLATPAK_SYSTEM_DIR:-/var/lib/flatpak}/overrides"
  for scope in user system; do
    flatpak_scope "$scope" "--$scope"
    flatpak list "--$scope" --app --columns=application > "$flatpaks/$scope-app-ids.txt"
    overrides="$user_overrides"
    [[ "$scope" == user ]] || overrides="$system_overrides"
    # Read legacy global reports from disk. Even `flatpak override --show`
    # may try to initialize a missing repo for this installation.
    if [[ -f "$overrides/global" && -r "$overrides/global" ]]; then
      cat -- "$overrides/global" > "$flatpaks/$scope-overrides.txt"
    fi
  done
  flatpak list --runtime --columns=ref,origin,installation > "$flatpaks/runtimes.tsv"
  flatpak --installations > "$flatpaks/system-installation-paths.txt"
  # --installations prints paths, not the IDs needed for --installation=NAME.
  # Capture remotes by ID from the same installation configuration as Flatpak.
  for conf in "${FLATPAK_CONFIG_DIR:-/etc/flatpak}"/installations.d/*.conf; do
    [[ -f "$conf" ]] || continue
    sed -nE 's/^[[:blank:]]*\[Installation "([^"]+)"\][[:space:]]*$/\1/p' "$conf"
  done | sort -u > "$flatpaks/named-installations.txt"
  while IFS= read -r name; do
    [[ "$name" != */* ]] || fail "invalid Flatpak installation ID: $name"
    flatpak_scope "named-$name" "--installation=$name"
  done < "$flatpaks/named-installations.txt"
  if [[ -d "$user_overrides" ]]; then
    cp -a -- "$user_overrides/." "$flatpaks/user-overrides/"
  fi
else
  printf 'Flatpak was not installed.\n' > "$flatpaks/not-installed.txt"
fi

# Keep the existing GNOME export on a GNOME desktop only. KDE state is backed up
# from the home filesystem, not by dumping GNOME schemas just because dconf exists.
case ":${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}:" in
  *:[Gg][Nn][Oo][Mm][Ee]:*|*:[Gg][Nn][Oo][Mm][Ee]-[Cc]lassic:*)
    mkdir -- "$stage"/{gnome,dconf}
    if command -v gnome-extensions >/dev/null; then
      for state in all enabled disabled; do
        args=()
        [[ "$state" == all ]] || args+=("--$state")
        gnome-extensions list "${args[@]}" > "$stage/gnome/extensions-$state.txt"
      done
      while IFS= read -r ext; do
        [[ -n "$ext" ]] || continue
        printf '## %s\n' "$ext"
        gnome-extensions info "$ext"
        printf '\n'
      done < "$stage/gnome/extensions-all.txt" > "$stage/gnome/extensions-info.txt"
    fi
    for scope in user system; do
      root="$data_home/gnome-shell/extensions"
      [[ "$scope" == user ]] || root=/usr/share/gnome-shell/extensions
      { if [[ -d "$root" ]]; then find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'; fi; } \
        > "$stage/gnome/extensions-$scope-installed.txt"
    done
    awk '/^gnome-shell-extension|^gnome-browser-connector/' "$packages/pacman-explicit-native.txt" > "$stage/gnome/gnome-extension-packages-native.txt"
    awk '/^gnome-shell-extension/' "$packages/foreign-explicit.txt" > "$stage/gnome/gnome-extension-packages-aur.txt"
    if command -v dconf >/dev/null; then
      for key in gnome gnome/shell gnome/shell/extensions gnome/desktop gnome/mutter gnome/settings-daemon; do
        dconf dump "/org/$key/" > "$stage/dconf/org-${key//\//-}.ini"
      done
    fi ;;
esac

home="$(realpath -e -- "$HOME")"
appimages="$stage/appimages"
# Traverse only the selected filesystem at each root, just like the home backup.
# A caller can name an AppImage file or an extra mount/subvolume explicitly.
for path in "$home" "${image_paths[@]}"; do
  root="$(realpath -e -- "$path")" || fail "AppImage source is missing: $path"
  find "$root" -xdev \
    \( -path "$home/.cache" -o -path "$home/.snapshots" -o -path "$home/.local/share/Trash" \) -prune -o \
    \( -type f -o \( -type l -xtype f \) \) -iname '*.AppImage' -print0
done | sort -zu > "$appimages/appimages.paths0"
touch -- "$appimages"/{appimages.txt,appimages.sha256.txt,appimages.symlinks.tsv}
while IFS= read -r -d '' file; do
  printf '%s\n' "$file" >> "$appimages/appimages.txt"
  sha256sum -- "$file" >> "$appimages/appimages.sha256.txt"
  if [[ -L "$file" ]]; then
    printf '%s\t%s\n' "$file" "$(realpath -e -- "$file")" >> "$appimages/appimages.symlinks.tsv"
  fi
done < "$appimages/appimages.paths0"

if [[ -d "$data_home/applications" ]]; then
  find "$data_home/applications" -type f -name '*.desktop' -print0 > "$stage/.launchers"
  while IFS= read -r -d '' file; do
    if grep -qiI -- appimage "$file"; then
      printf '%s\n' "$file"
    elif (($? != 1)); then
      fail "cannot read launcher: $file"
    fi
  done < "$stage/.launchers" > "$appimages/appimage-desktop-files.txt"
  rm -- "$stage/.launchers"
else
  touch -- "$appimages/appimage-desktop-files.txt"
fi

# Publish only complete output. mv -n can skip an existing target with status 0.
mv -nT -- "$stage" "$out"
[[ ! -e "$stage" ]] || fail "output already exists: $out"
printf '%s\n' "$out"
