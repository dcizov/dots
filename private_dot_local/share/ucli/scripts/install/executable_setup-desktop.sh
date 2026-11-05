#!/usr/bin/env bash
# Set up a desktop environment and snapshot afterwards.
#
# Usage: sudo setup-desktop.sh [--choose] [--no-snapshot] [--force] [gnome|hyprland|kde]
#
# Installs the desktop package set, then the firefox + terminal pair that desktop
# is configured for, then the shell tier, then GNOME extensions, then applies the
# dotfiles that need those programs to exist, then configures Firefox (profile,
# Betterfox user.js, GNOME theme), then snapshots as "<DE> Setup".
#
# The package set is DESKTOP_<DE>_BASE + DESKTOP_<DE>_ADDITIONS + SERVICES_<DE>
# from packages.bash — this script holds no package list of its own, so
# `install-packages.sh desktop`, `--choose` and this step cannot drift apart.
#
# What the desktop group carries but this repo does not want (epiphany,
# gnome-console, gnome-software, gnome-tour, gnome-user-docs, malcontent, yelp on
# GNOME) is DESKTOP_REMOVE_<DE>: skipped at install with `--ignore`, and removed
# afterwards when they are already there — the archinstall case — with a snapshot
# taken first.
#
# Intended for Arch minimal (archinstall) post-console-first-boot flow:
#   1. curl -fsSL .../dcizov/dots/main/install.sh | bash   # git, chezmoi, just, ucli
#   2. ucli setup-snapshots        # snapper + limine, snapshot #1 (btrfs)
#   3. ucli setup-system gnome     # base packages, then this script
#   4. ucli devmode / ucli apps    # optional extras
#
# Run it plainly, or with --no-snapshot to install without the "<DE> Setup"
# restore point (the same flag every other snapshot in the repo honours).
# --force re-runs the gated Firefox steps (Betterfox copy, GNOME theme).
#
# Everything a TTY-only machine needs before step 3 is ucli itself: until the
# desktop exists, .chezmoiignore keeps ~/.zshrc, starship, ~/.config/ghostty and
# ~/.config/ucli/firefox out of $HOME, so the fresh-install snapshot stays minimal.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

choose=0
take_snapshot=1
firefox_force=0
while (($#)); do
  case "$1" in
    --choose) choose=1 ;;
    --no-snapshot) take_snapshot=0 ;;
    --force) firefox_force=1 ;;
    --help|-h)
      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 [--choose] [--no-snapshot] [--force] <gnome|hyprland|kde>" >&2
  exit 1
fi

desktop="${1:-}"

# Auto-detect desktop: CLI arg → chezmoi profile → environment → installed pkgs
if [[ -z "$desktop" ]]; then
  # chezmoi profile value (set during initial setup)
  if command -v chezmoi >/dev/null 2>&1; then
    desktop="$(chezmoi data 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("desktop","none"))' 2>/dev/null || echo none)"
  fi
fi
if [[ -z "$desktop" || "$desktop" == "none" || "$desktop" == "auto" ]]; then
  # Environment / detected desktop session
  desktop="$(detect_desktop 2>/dev/null || echo none)"
fi
if [[ -z "$desktop" || "$desktop" == "none" ]]; then
  # Installed desktop packages as last resort
  if pacman -Q gnome-shell >/dev/null 2>&1; then desktop="gnome"
  elif { pacman -Q plasma-desktop >/dev/null 2>&1 || pacman -Q plasma-meta >/dev/null 2>&1; }; then desktop="kde"
  elif pacman -Q hyprland >/dev/null 2>&1; then desktop="hyprland"
  fi
fi
if [[ -z "$desktop" || "$desktop" == "none" ]]; then
  desktop="$(ui_choose "Which desktop?" \
    'gnome|GNOME Shell' 'hyprland|Hyprland' 'kde|KDE Plasma')" || exit 2
fi
case "$desktop" in
  gnome|hyprland|kde) ;;
  *) echo "Invalid desktop: $desktop" >&2; exit 2 ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"

# One snapshot script for the whole repo: the "before removing …" restore point
# below and the "<DE> Setup" one at the end both go through it.
snapshot_script="$script_dir/../system/snapshot-fresh-install.sh"

# Resolve the AUR helper (distro-aware: AUR_HELPER from packages.bash when set,
# else whatever is installed, else the distro default — nothing is cached).
# Run as the real user since this may install the helper via makepkg (no root).
aur_helper="$(runuser -u "$real_user" -- "$script_dir/install-aur-helper.sh")"
echo "AUR helper: $aur_helper"

# Install this desktop's packages: BASE (what a session needs) + ADDITIONS (merely
# convenient) + its services (gdm/sddm are packages too). The group is installed
# whole — a hand-picked subset is how a session ends up without a settings daemon —
# minus DESKTOP_REMOVE_<DE>, which is passed as `--ignore` so it never lands.
# Packages the arrays list that are not in the repos go to the AUR helper.
install_desktop() {
  local de="$1"
  local remove_var="DESKTOP_REMOVE_${de^^}"
  local -a unwanted=()
  if [[ -n "${!remove_var:-}" ]]; then
    local -n unwanted_ref="$remove_var"
    unwanted=("${unwanted_ref[@]}")
  fi

  local base_var="DESKTOP_${de^^}_BASE"
  local add_var="DESKTOP_${de^^}_ADDITIONS"
  local svc_var="SERVICES_${de^^}"
  local -a all_pkgs=()
  local -n base_ref="$base_var" add_ref="$add_var" svc_ref="$svc_var"
  all_pkgs=("${base_ref[@]}" "${add_ref[@]}" "${svc_ref[@]}")

  local ignore_csv=""
  if (( ${#unwanted[@]} )); then
    ignore_csv="$(IFS=,; printf '%s' "${unwanted[*]}")"
  fi

  local -a aur_pkgs=()
  for pkg in "${all_pkgs[@]}"; do
    if pacman -Si "$pkg" >/dev/null 2>&1 || pacman -Sgq "$pkg" >/dev/null 2>&1; then
      # --ignore is what keeps the unwanted group members out of a fresh install;
      # it is harmless for the single packages in the arrays (none of them is on
      # the list). A package that some other target *requires* would make pacman
      # refuse the transaction — none of these is required by anything.
      local -a ignore_args=()
      [[ -n "$ignore_csv" ]] && ignore_args=("--ignore=$ignore_csv")
      sudo pacman -S --needed --noconfirm ${ignore_args[@]+"${ignore_args[@]}"} "$pkg"
    else
      # Not in the repos is not "missing": the KDE terminal lives in the AUR as
      # kwi-git. The helper is already resolved above, so hand those over to it.
      aur_pkgs+=("$pkg")
    fi
  done

  if (( ${#aur_pkgs[@]} )); then
    echo "AUR packages: ${aur_pkgs[*]}"
    case "$aur_helper" in
      paru)   runuser -u "$real_user" -- paru -S --needed "${aur_pkgs[@]}" \
                || echo "warning: AUR install failed (${aur_pkgs[*]}); run 'ucli apps' later" >&2 ;;
      shelly) runuser -u "$real_user" -- shelly install aur "${aur_pkgs[@]}" --needed --no-confirm \
                || echo "warning: AUR install failed (${aur_pkgs[*]}); run 'ucli apps' later" >&2 ;;
      *)      echo "warning: no AUR helper; install ${aur_pkgs[*]} by hand" >&2 ;;
    esac
  fi
}

if (( choose )); then
  # Interactive: pick which groups to install. Every group is a packages.bash
  # array — core is BASE, extras is ADDITIONS, plus the terminal and the browser
  # this desktop is configured for — so this menu cannot drift from the arrays.
  declare -A groups=()
  declare -A pkgs=()

  add_group() {
    local name="$1" desc="$2" arr="$3"
    local -a items=()
    local -n ref="$arr"
    items=("${ref[@]}")
    ((${#items[@]})) || return 0          # an empty array is not offered
    groups[$name]="$desc"
    pkgs[$name]="$(printf '%s ' "${items[@]}")"
  }

  add_group core "${desktop} session (required)" "DESKTOP_${desktop^^}_BASE"
  add_group extras "optional ${desktop} apps and tools" "DESKTOP_${desktop^^}_ADDITIONS"
  case "$desktop" in
    gnome)
      add_group apps "GNOME extras: boxes, Nautilus extensions" GNOME_APP_OVERRIDES
      add_group terminal "Terminal (ghostty, the configured one)" DESKTOP_TERMINAL_GNOME
      ;;
    hyprland)
      add_group terminal "Terminal (ghostty, the configured one)" DESKTOP_TERMINAL_HYPRLAND
      ;;
    kde)
      add_group terminal "Terminal (kwi — KDE's new one; AUR kwi-git, else Konsole from plasma)" DESKTOP_TERMINAL_KDE
      ;;
  esac
  add_group browser "Firefox (the configured browser)" DESKTOP_BROWSER

  echo "Select $desktop package groups to install:"
  echo
  items=()
  # core was added first on purpose: it stays first in the menu.
  for name in core extras apps terminal browser; do
    [[ -n "${groups[$name]:-}" ]] && items+=("$name — ${groups[$name]}")
  done
  sorted=("${items[@]}")

  # Same multi-select as `ucli devmode`, so this menu behaves identically: space
  # toggles, enter confirms, and the numbered prompt is the no-gum fallback.
  chosen=()
  menu_args=()
  # the session group is required, so start with it ticked
  if (( ${#sorted[@]} )); then menu_args+=(--selected "${sorted[0]}"); fi
  if picked="$(ui_choose_multi "$desktop packages" --height 10 \
        "${menu_args[@]}" "${sorted[@]}")"; then
    while IFS= read -r line; do
      [ -n "$line" ] && chosen+=("$line")
    done <<<"$picked"
  fi

  if (( ${#chosen[@]} == 0 )); then
    echo "No groups selected. Aborting."
    exit 1
  fi

  install_pkgs=()
  for c in "${chosen[@]}"; do
    gname="${c%% — *}"
    # The group's packages were stored space-separated (it is a word list).
    read -r -a group_items <<<"${pkgs[$gname]:-}"
    install_pkgs+=("${group_items[@]}")
  done

  aur_pkgs=()
  for pkg in "${install_pkgs[@]}"; do
    if pacman -Si "$pkg" >/dev/null 2>&1 || pacman -Sgq "$pkg" >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm "$pkg"
    else
      # Not in the repos is not "missing": kwi lives in the AUR as kwi-git. The
      # helper is already resolved above, so hand those over to it.
      aur_pkgs+=("$pkg")
    fi
  done
  if (( ${#aur_pkgs[@]} )); then
    echo "AUR packages: ${aur_pkgs[*]}"
    case "$aur_helper" in
      paru)   runuser -u "$real_user" -- paru -S --needed "${aur_pkgs[@]}" \
                || echo "warning: AUR install failed (${aur_pkgs[*]}); run 'ucli apps' later" >&2 ;;
      shelly) runuser -u "$real_user" -- shelly install aur "${aur_pkgs[@]}" --needed --no-confirm \
                || echo "warning: AUR install failed (${aur_pkgs[*]}); run 'ucli apps' later" >&2 ;;
      *)      echo "warning: no AUR helper; install ${aur_pkgs[*]} by hand" >&2 ;;
    esac
  fi
else
  # Full desktop package set from the arrays.
  install_desktop "$desktop"
fi

# Take out what this repo does not want from the desktop group
# (DESKTOP_REMOVE_<DE>). On a machine where this repo installed the desktop the
# group install above already skipped them with --ignore and this is a no-op; it
# exists for the archinstall case, where the GNOME profile installed the whole
# group beforehand, and for machines that predate the list.
#
# The removal is preceded by a snapshot: `pacman -Rns` is not reversible, and the
# restore point is free. --no-snapshot / UCLI_NO_SNAPSHOT=1 skip it, like every
# other snapshot in the repo.
remove_desktop_unwanted() {
  local de="$1"
  local remove_var="DESKTOP_REMOVE_${de^^}"
  [[ -n "${!remove_var:-}" ]] || return 0
  local -n remove_ref="$remove_var"

  local -a present=()
  local pkg
  for pkg in "${remove_ref[@]}"; do
    [[ -n "$pkg" ]] || continue
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      present+=("$pkg")
    fi
  done
  if (( ${#present[@]} == 0 )); then
    echo "nothing to remove from the $de group (all ${#remove_ref[@]} already absent)"
    return 0
  fi

  echo
  echo "Not wanted from the $de group: ${present[*]}"
  if (( take_snapshot )) && [[ -x "$snapshot_script" ]]; then
    echo "Creating a snapshot before removing them ..."
    "$snapshot_script" "before removing ${de} group packages" \
      || echo "warning: snapshot failed; continuing (Ctrl-C now to abort)" >&2
  fi

  # One transaction first: it lets pacman resolve their now-orphaned dependencies
  # (-s) together. If something installed still requires one of them the whole
  # transaction is refused, so fall back to per-package attempts and say which
  # ones are held back instead of pretending the set was removed.
  local rc=0
  pacman -Rns --noconfirm "${present[@]}" || rc=$?
  if (( rc != 0 )); then
    echo "one transaction was refused; removing one at a time ..." >&2
    local -a still=()
    for pkg in "${present[@]}"; do
      pacman -Q "$pkg" >/dev/null 2>&1 || continue
      if ! pacman -Rns --noconfirm "$pkg"; then
        still+=("$pkg")
      fi
    done
    if (( ${#still[@]} )); then
      echo "warning: could not remove: ${still[*]}" >&2
      echo "         something installed still requires them; remove that first and" >&2
      echo "         re-run: sudo ucli setup-desktop $de" >&2
    fi
  fi

  # Verify: this is a list of packages that must not be there afterwards.
  local -a leftover=()
  for pkg in "${present[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 && leftover+=("$pkg")
  done
  if (( ${#leftover[@]} )); then
    echo "warning: still installed: ${leftover[*]}" >&2
    return 1
  fi
  echo "removed ${#present[@]} package(s) from the $de group"
}

# Not fatal: a package that something else requires is a reason to say so, not to
# leave the machine without a shell, a browser or a snapshot.
remove_desktop_unwanted "$desktop" \
  || echo "warning: part of the ${desktop} group's unwanted set stayed installed (see above)" >&2

# Enable this desktop's session manager (SERVICES_GNOME = gdm, SERVICES_HYPRLAND
# and SERVICES_KDE = sddm). Same arrays install-packages.sh uses; installing the
# package is not the same as enabling the unit, and until now only GDM was
# enabled (at the top of this script, before the package existed).
svc_var="SERVICES_${desktop^^}"
declare -n svc_ref="$svc_var"
for svc in "${svc_ref[@]}"; do
  if systemctl enable "$svc.service" 2>/dev/null; then
    echo "enabled $svc.service"
  else
    echo "warning: could not enable $svc.service (installed but not started)" >&2
  fi
done

# ucli's own runtime first: gum (menus) and python-pipx (gext). `base` installs
# these too, but the fresh-install flow is setup-desktop -> devmode -> apps, so
# they have to land here as well or the gext step below fails.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" ucli-runtime || true
fi

# Fonts and themes the shipped configs and dconf profile reference (JetBrains
# Mono / Nerd Font for ghostty + VSCodium, adw-gtk3 for GTK3 apps, Adwaita icons)
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" fonts
fi

# Microsoft core fonts (Arial, Times New Roman, …) come from the AUR and are
# built here rather than in the repo-font step: the build downloads from
# SourceForge, and losing a desktop setup over a font would be silly. Visible,
# non-fatal, retryable with `ucli ms-fonts`.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" --yes fonts-ms \
    || echo "warning: Microsoft core fonts failed; retry with 'ucli ms-fonts'" >&2
fi

# The desktop's own apps: firefox (the configured browser, on every desktop) plus
# the terminal that desktop is configured for — ghostty on gnome/hyprland, kwi on
# kde (AUR kwi-git today; Konsole from the plasma group is the safety net). The DE
# install above only covers the DE packages and the removal list, and it never
# installs a terminal it would then have two of.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" essentials || true
fi

# The shell tier (zsh + oh-my-zsh + plugins + starship) belongs to this step too:
# `ucli setup-system` is the only machine-setup command a fresh install runs, so
# if the shell waited for `ucli cli` you would boot into bash with no prompt.
# Packages as root, then the user-owned part (omz, plugin clones, chsh) as the
# real user — oh-my-zsh must never end up root-owned.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" shell-tools || true
fi

# Deploy the dotfiles that only make sense now that the desktop exists: ~/.zshrc,
# starship, ~/.config/<terminal>, ~/.config/ucli/firefox. .chezmoiignore checks for the
# programs with lookPath, so a TTY-only box gets none of them — this is the apply
# that makes them appear. Runs as the real user (root-owned $HOME would be wrong)
# and is not fatal: a machine without chezmoi initialized still gets a desktop.
if [[ -x "$(command -v chezmoi || true)" ]] && [[ -d "$real_home/.local/share/chezmoi" ]]; then
  echo "Applying dotfiles for $real_user (shell, terminal, browser configs) ..."
  runuser -u "$real_user" -- env HOME="$real_home" chezmoi apply -v \
    || echo "warning: chezmoi apply failed; run 'ucli chezmoi-apply' as $real_user" >&2
else
  echo "note: chezmoi not initialized for $real_user; run 'ucli chezmoi-apply' after bootstrap." >&2
fi

if [[ -x "$script_dir/install-shell.sh" ]]; then
  echo "Setting up the shell (oh-my-zsh, plugins, starship) for $real_user ..."
  runuser -u "$real_user" -- env UCLI_SKIP_PACKAGES=1 "$script_dir/install-shell.sh" \
    || echo "warning: shell setup failed; run 'ucli cli' as $real_user" >&2
fi

# GNOME extensions are handled by the extension-set script via gext.
# Ensure gext is installed (via pipx) before installing extensions.
if [[ "$desktop" == "gnome" ]]; then
  extension_failed=0
  # Add user's pipx bin to PATH when running as root
  if [[ "$EUID" -eq 0 ]] && [[ -d "$real_home/.local/bin" ]]; then
    export PATH="$real_home/.local/bin:$PATH"
  fi
  if ! command -v gext >/dev/null 2>&1; then
    echo "gext (gnome-extensions-cli) not found; installing it as $real_user ..."
    # As the real user and through its own script: pipx installs into
    # $HOME/.local, so root's HOME would put gext where the desktop session never
    # looks, and the script is the one place that knows what "installed" means and
    # what to say when pipx itself is missing (it is not fatal here — the desktop
    # is already up).
    if runuser -u "$real_user" -- env HOME="$real_home" \
         "$script_dir/install-gnome-extensions-cli.sh"; then
      export PATH="$real_home/.local/bin:$PATH"
    else
      extension_failed=1
    fi
  fi
  # System extensions first, then user/personal overrides. Neither failure may
  # take the desktop down with it, but neither may be silent either: `|| true` on
  # these two lines is how a machine ended up with no extensions and no error.
  if ! "$script_dir/install-gnome-extension-set.sh" managed; then
    extension_failed=1
  fi
  # personal set: only when ~/.config/ucli/packages.local.bash defines one; the
  # script exits 0 with a note when it does not.
  if ! "$script_dir/install-gnome-extension-set.sh" personal; then
    extension_failed=1
  fi
  # The curated settings, after the extensions they refer to: dash-to-dock's and
  # blur-my-shell's schemas only exist once those are installed, and
  # gnome-defaults skips what it cannot find. Cosmetic, so not fatal — but never
  # silent either.
  if [[ -x "$script_dir/gnome-defaults.sh" ]]; then
    if ! runuser -u "$real_user" -- env HOME="$real_home" "$script_dir/gnome-defaults.sh"; then
      echo "warning: some GNOME defaults were not applied; re-run as $real_user: ucli gnome-defaults" >&2
    fi
  fi
  # Flatpaks get the theme through a runtime extension, not through /usr/share —
  # only when flatpak is already on the machine; `ucli apps` installs flatpak and
  # runs the same step, which is the normal order for a first install.
  if command -v flatpak >/dev/null 2>&1 && [[ -x "$script_dir/install-flatpak-gtk-theme.sh" ]]; then
    "$script_dir/install-flatpak-gtk-theme.sh" \
      || echo "warning: Flatpak GTK theme extension not installed; re-run: ucli flatpak-theme" >&2
  fi
  if [[ "${extension_failed:-0}" == 1 ]]; then
    {
      echo
      echo "warning: the GNOME extension set did not install completely."
      echo "  the desktop itself is fine; extensions are the missing piece."
      echo "  retry as your user (not root): ucli setup-extensions --force"
    } >&2
  fi
fi

# Firefox ships configured: the profile, the Betterfox user.js and (on GNOME) the
# GNOME theme are part of installing the browser, not of the later `ucli apps`
# step. Runs after the chezmoi apply above so ~/.config/ucli/firefox/user.js
# exists, and as the real user so the profile is user-owned. Not fatal.
if [[ -x "$script_dir/install-firefox-profile.sh" ]]; then
  fx_label="Betterfox"
  [[ "$desktop" == "gnome" ]] && fx_label="Betterfox + GNOME theme"
  echo "Configuring Firefox for $real_user ($fx_label) ..."
  fx_args=()
  (( firefox_force )) && fx_args+=(--force)
  runuser -u "$real_user" -- env HOME="$real_home" "$script_dir/install-firefox-profile.sh" \
    ${fx_args[@]+"${fx_args[@]}"} \
    || echo "warning: Firefox profile setup failed; run 'ucli apps' as $real_user" >&2
fi

# Create a snapshot capturing the DE-installed state. Not fatal: on a machine
# where `ucli setup-snapshots` has not run yet there is no snapper config, and
# failing the whole desktop setup over a restore point would be silly.
# One snapshot script for the whole repo; --no-snapshot / UCLI_NO_SNAPSHOT=1 skip it.
snapshot_args=()
(( take_snapshot )) || snapshot_args+=(--no-snapshot)
"$script_dir/../system/snapshot-fresh-install.sh" "${snapshot_args[@]}" "$desktop Setup" \
  || echo "warning: snapshot failed; run 'ucli snapshot' afterwards" >&2

echo "Desktop $desktop installed and snapshot created."
echo "Next: log out and back in (zsh + extensions), then 'ucli devmode' and 'ucli apps'."
echo "To backup GNOME settings: ucli backup-gnome-settings"
