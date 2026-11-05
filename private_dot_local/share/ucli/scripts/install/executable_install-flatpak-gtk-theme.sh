#!/usr/bin/env bash
set -uo pipefail

# adw-gtk3 for Flatpak apps: the theme extension, installed up front.
#
# Why this exists at all: a Flatpak app cannot see the host's /usr/share/themes —
# /usr is reserved inside the sandbox — so "the GTK theme is set with gsettings"
# is only half the configuration. GTK3 apps in the sandbox get their theme from a
# runtime extension named after the theme, org.gtk.Gtk3theme.<name>.
#
# What Flatpak's own documentation says (docs.flatpak.org, "Desktop Integration →
# Installing themes → Instructions for Gtk themes"):
#
#   "As of Flatpak 0.10.1, Flatpak can automatically detect the active Gtk theme
#    on the host by reading the value of the `gtk-theme` DConf key. If the
#    corresponding theme is packaged as an extension in the remote, Flatpak will
#    automatically install it during `flatpak install` or `flatpak update`."
#
# So the automatic path exists — but it is lazy: the extension appears on the next
# flatpak install/update, which on a fresh machine may be minutes or weeks after
# the first Flatpak app tried to look right. adw-gtk3 is packaged on Flathub (both
# variants, x86_64 and aarch64), which is the case Flatpak's docs call the good one
# and what adw-gtk3's own README tells you to install:
#
#   flatpak install org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark
#
# ArchWiki sends you the same way ("Flatpak applications not picking up the default
# system theme: The easiest solution is using themes that are available in
# Flathub"), and warns that the alternative — handing the sandbox your theme files
# with `flatpak override --filesystem=xdg-data/themes` — weakens the sandbox and
# needs the theme copied out of /usr first, because /usr is never shared. That
# alternative is therefore not implemented here; this is the supported path.
#
# Idempotent: an already-installed extension is a no-op, and font/theme extensions
# follow their runtime's branch, so `flatpak update` keeps it current.
#
# Usage: install-flatpak-gtk-theme.sh [--dry-run] [--system] [--user]

dry_run=0
scope="--user"
usage() {
  cat <<'USAGE'
usage: install-flatpak-gtk-theme.sh [--dry-run] [--user|--system]

Installs the adw-gtk3 GTK theme runtime extensions from Flathub so Flatpak GTK3
apps use the same theme as the host (adw-gtk3-dark, set by gnome-defaults.sh).

  --user        install for this user (default; matches install-flatpaks.sh)
  --system      install system-wide (needs root, and the apps must be system-wide)
  --dry-run     print the flatpak commands, change nothing
USAGE
}
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    --user) scope="--user" ;;
    --system) scope="--system" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

# When run via sudo, $HOME is root's home; Flatpak's per-user installation lives in
# the invoking user's, so resolve that the same way the other install scripts do.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" 2>/dev/null | cut -d: -f6 || true)"
[[ -n "$real_home" ]] || real_home="${HOME:-}"

# Extensions are named after the theme, not after the package: the Arch package is
# adw-gtk-theme and it ships the themes adw-gtk3 and adw-gtk3-dark. Both variants go
# in (the pair is one 128 KiB download each and upstream's README installs both), so
# switching the host back to the light variant does not need this step re-run.
extensions=(org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark)
theme_names=(adw-gtk3 adw-gtk3-dark)

# `ucli setup-system gnome` runs this under sudo. With --user that would install
# into root's Flatpak store (/root/.local/share/flatpak), which no desktop session
# ever reads, so re-exec as the invoking user. --system is the case that wants root.
if [[ "$scope" == "--user" ]] && [[ "${EUID:-$(id -u)}" -eq 0 ]] \
   && [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != root ]]; then
  exec runuser -u "$real_user" -- env HOME="$real_home" \
    PATH="$real_home/.local/bin:$PATH" "$0" "$@"
fi

# flatpak comes with `ucli apps`; a machine without it has no sandbox to theme.
if ! command -v flatpak >/dev/null 2>&1; then
  echo "flatpak is not installed; no Flatpak theme extension to add"
  echo "  (the Flatpak step installs flatpak first: ucli apps)"
  exit 0
fi

# The host half. Without adw-gtk-theme the gtk-theme key cannot be set either
# (gnome-defaults skips it), so say that instead of only installing the extension.
host_theme=""
for name in "${theme_names[@]}"; do
  for dir in "/usr/share/themes/$name" "$real_home/.local/share/themes/$name"; do
    [[ -d "$dir" ]] || continue
    host_theme="$name"
    break 2
  done
done
# The active theme, as the user has it right now. Flatpak reads exactly this key
# (the docs quote `gtk-theme`), so it is also the answer to "will this be used?".
active_theme=""
if command -v gsettings >/dev/null 2>&1; then
  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    active_theme="$(runuser -u "$real_user" -- env HOME="$real_home" \
      gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
  else
    active_theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
  fi
fi
active_theme="${active_theme//\'/}"

echo "flatpak theme extensions: ${extensions[*]}"
echo "scope: $scope${host_theme:+ (host theme: $host_theme)}${active_theme:+, gtk-theme: $active_theme}"

if [[ "$scope" == "--system" ]] && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "error: --system needs root: sudo ucli flatpak-theme --system" >&2
  exit 1
fi

if [[ -z "$host_theme" ]]; then
  echo "warning: adw-gtk3 is not installed on the host, so Flatpak apps would get the" >&2
  echo "         extension but no matching theme to apply." >&2
  echo "         install it first: sudo pacman -S adw-gtk-theme" >&2
fi

if (( dry_run )); then
  echo "+ flatpak remote-add $scope --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
  echo "+ flatpak install $scope -y flathub ${extensions[*]}"
  exit 0
fi

# Flathub first: the extensions come from there, and a per-user installation does
# not necessarily have the remote yet (`flatpak remote-add` is what install-flatpaks
# does for apps; this is the same line for the case where that step has not run).
if ! flatpak remotes $scope --columns=name 2>/dev/null | grep -qx flathub; then
  if ! flatpak remote-add "$scope" --if-not-exists flathub \
       https://flathub.org/repo/flathub.flatpakrepo; then
    echo "error: could not add the flathub remote ($scope)" >&2
    exit 1
  fi
  echo "added flathub ($scope)"
fi

# Only install what is missing, so a rerun says "already installed" instead of
# resolving the remote again (and so a machine without network is not hammered).
installed="$(flatpak list $scope --runtime --columns=application 2>/dev/null || true)"
missing=()
for extension in "${extensions[@]}"; do
  if grep -qx "$extension" <<<"$installed"; then
    echo "  $extension: already installed"
  else
    missing+=("$extension")
  fi
done

rc=0
if ((${#missing[@]})); then
  echo "installing: ${missing[*]}"
  if ! flatpak install "$scope" -y flathub "${missing[@]}"; then
    echo "error: flatpak could not install the theme extension(s)" >&2
    rc=1
  fi
fi

# Verify rather than trust the exit code: this is the whole point of the step.
installed="$(flatpak list $scope --runtime --columns=application 2>/dev/null || true)"
verified=0
for extension in "${extensions[@]}"; do
  grep -qx "$extension" <<<"$installed" && verified=$((verified + 1))
done

if (( rc == 0 )); then
  echo "flatpak theme: $verified/${#extensions[@]} adw-gtk3 extension(s) installed ($scope)"
  echo "GTK3 Flatpak apps pick the theme up from the host's gtk-theme key; restart"
  echo "one that is already running. libadwaita apps (most GNOME apps) ignore it —"
  echo "they follow the Settings portal's color-scheme instead."
fi
exit "$rc"
