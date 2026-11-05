#!/usr/bin/env bash
set -euo pipefail

# Install/enable GNOME Shell extensions using gnome-extensions-cli (gext).
#
# Usage:
#   install-gnome-extension-set.sh managed   # the repo's set (GNOME_MANAGED_EXTENSIONS)
#   install-gnome-extension-set.sh personal  # your own (PERSONAL_GNOME_EXTENSIONS)
#
# "managed" and "personal" are both installed per user, into ~/.local/share/
# gnome-shell/extensions; gnome-shell's own /usr/share directory — Extension
# Manager's "System Extensions" — is pacman's business (GNOME_SYSTEM_EXTENSION_PACKAGES).
#
# Package-based extensions (gnome-shell-extensions, etc.) are installed via
# pacman/paru by install-packages.sh. This script handles non-repo extensions
# via gext (gnome-extensions-cli) and enables all extensions.
#
# Enabling is ONE write to org.gnome.shell enabled-extensions instead of N
# `gext enable` calls (adapted from Bluefin, which sets the whole list in its
# gschema override). The existing list is preserved and merged, so extensions
# the user enabled themselves are never dropped.
#
# Pruning: the UUIDs this repo installed are recorded in
# ~/.local/state/ucli/gnome-extensions.installed, and every run subtracts the
# wanted set (managed ∪ personal ∪ Gradia, so the two modes cannot prune each
# other) from that manifest before installing anything. What is left over is an
# extension you deleted from the arrays: it gets disabled and, when it lives in
# ~/.local/share/gnome-shell/extensions, uninstalled. Extensions you installed
# yourself are absent from the manifest and are never touched. That is the only
# way to tell "removed from the list" apart from "the user wanted this" — a diff
# of enabled-extensions cannot.
#
# Source: https://github.com/essembeh/gnome-extensions-cli

usage() {
  cat <<'USAGE'
usage: install-gnome-extension-set.sh [managed|personal] [--force]

  managed   the repo's set (user-theme, dash-to-dock, blur-my-shell, gsconnect,
            just-perfection, logo-menu, tray icons) plus Gradia Capture, which is
            built from its own pinned upstream commit because it is on neither EGO
            nor in the repos; the repo-packaged ones (caffeine, appindicator) come
            from install-packages.sh. "managed", not "system": gext writes to
            ~/.local/share/gnome-shell/extensions, so these are *user* extensions —
            the "System Extensions" section only ever holds pacman's.
  personal  your own, from PERSONAL_GNOME_EXTENSIONS in
            ~/.config/ucli/packages.local.bash
  --force   run even when the gate says this set is unchanged
  system    accepted as a legacy alias for managed
USAGE
}

mode="managed"
force=0
for arg in "$@"; do
  case "$arg" in
    managed|personal) mode="$arg" ;;
    # Legacy name from when this script called the repo's set "system" — exactly
    # the confusion the rename fixes: nothing here lands in /usr/share.
    system) mode=managed ;;
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done


# When run via sudo (from setup-desktop.sh), $HOME is root's home;
# use the invoking user's home instead.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# gext is installed by pipx to $real_home/.local/bin; add it to PATH
# when running as root so command -v gext finds it.
if [[ "$EUID" -eq 0 ]] && [[ -d "$real_home/.local/bin" ]]; then
  export PATH="$real_home/.local/bin:$PATH"
fi

# Optional personal overlay: PERSONAL_GNOME_EXTENSIONS, "PK:UUID" pairs.
personal_file="$real_home/.config/ucli/packages.local.bash"
# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"
if [[ -r "$personal_file" ]]; then
  # shellcheck source=/dev/null
  source "$personal_file"
fi
# shellcheck source=/dev/null
source "$real_home/.local/share/ucli/scripts/lib/detect.sh"

# Run a command as the real user (not root) when invoked via sudo.
# Extensions and dconf are per-user: as root they would land in root's
# profile/database instead of the user's. HOME is forced too, because dconf
# resolves its database from it.
as_user() {
  if [[ "$EUID" -eq 0 ]] && [[ -n "$SUDO_USER" ]]; then
    runuser -u "$real_user" -- env -u XDG_CONFIG_HOME HOME="$real_home" \
      PATH="$real_home/.local/bin:$PATH" "$@"
  else
    "$@"
  fi
}

run_gext() { as_user gext "$@"; }

# Current enabled list, one UUID per line.
enabled_extensions() {
  local raw=""
  if command -v dconf >/dev/null 2>&1; then
    raw="$(as_user dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || true)"
  fi
  if [[ -z "$raw" ]] && command -v gsettings >/dev/null 2>&1; then
    raw="$(as_user gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
  fi
  [[ -n "$raw" ]] || return 0
  printf '%s\n' "$raw" | grep -o "'[^']*'" | tr -d "'" || true
}

# --- enabled-extensions, written once ---------------------------------------

# Write exactly this list to org.gnome.shell enabled-extensions, once. Both
# enable_uuids (merge in what the set wants) and disable_uuids (prune what it no
# longer wants) end here, so one place knows the key, the literal format and the
# gsettings fallback.
write_enabled_list() {
  local -a list=("$@")
  local literal="[" i
  for i in "${!list[@]}"; do
    (( i )) && literal+=", "
    literal+="'${list[$i]}'"
  done
  literal+="]"

  if command -v dconf >/dev/null 2>&1 &&
     as_user dconf write /org/gnome/shell/enabled-extensions "$literal" 2>/dev/null; then
    echo "  enabled-extensions = $literal"
    return 0
  fi
  if command -v gsettings >/dev/null 2>&1 &&
     as_user gsettings set org.gnome.shell enabled-extensions "$literal" 2>/dev/null; then
    echo "  enabled-extensions = $literal"
    return 0
  fi

  echo "warning: single-write failed; falling back to per-extension gext enable" >&2
  local u
  for u in "${list[@]}"; do
    [[ -n "$u" ]] || continue
    run_gext enable "$u" >/dev/null 2>&1 || echo "warning: could not enable $u (may need shell restart)" >&2
  done
}

# enable_uuids <uuid...> — merge into the current list and write it once.
enable_uuids() {
  (($#)) || return 0

  local -a current=() merged=()
  mapfile -t current < <(enabled_extensions)
  ((${#current[@]})) && merged=("${current[@]}")

  local uuid existing
  for uuid in "$@"; do
    [[ -n "$uuid" ]] || continue
    for existing in "${merged[@]:-}"; do
      [[ "$existing" == "$uuid" ]] && continue 2
    done
    merged+=("$uuid")
  done

  local current_joined="" merged_joined=""
  ((${#current[@]})) && current_joined="$(printf '%s,' "${current[@]}")"
  ((${#merged[@]})) && merged_joined="$(printf '%s,' "${merged[@]}")"

  if [[ "$current_joined" == "$merged_joined" ]]; then
    echo "enabled-extensions already up to date (${#merged[@]} entries)"
    return 0
  fi

  write_enabled_list "${merged[@]}"
}

# disable_uuids <uuid...> — drop them from the current list and write it once.
disable_uuids() {
  (($#)) || return 0

  local -a current=() keep=()
  mapfile -t current < <(enabled_extensions)
  ((${#current[@]})) || return 0

  local existing uuid drop
  for existing in "${current[@]}"; do
    drop=0
    for uuid in "$@"; do
      [[ "$existing" == "$uuid" ]] && drop=1
    done
    (( drop )) || keep+=("$existing")
  done
  ((${#keep[@]} == ${#current[@]})) && return 0

  write_enabled_list "${keep[@]}"
}

# Check if a GNOME extension UUID is already installed.
is_extension_installed() {
  local uuid="$1"
  run_gext list 2>/dev/null | grep -qF "$uuid"
}

# Install an extension from extensions.gnome.org by primary key.
# Skips if the extension UUID is already installed (idempotent re-runs).
install_extension_by_pk() {
  local pk="$1" uuid="$2"

  if [[ -n "$uuid" ]] && is_extension_installed "$uuid"; then
    echo "extension pk=$pk ($uuid) already installed; skipping"
    return 0
  fi

  echo "installing extension pk=$pk ..."
  local out
  if ! out="$(run_gext install "$pk" 2>&1)"; then
    echo "warning: could not install extension pk=$pk ($uuid)" >&2
    printf '%s\n' "$out" | tail -3 | sed 's/^/    /' >&2
    return 1
  fi
}

# `gext list` is local (no network), so asking it is cheap. It is also the only
# way to tell "already done" from "recorded as done" — a gate committed after a
# failed install used to make this script print "unchanged; skipping" on every
# later run, with no extensions installed.
gext_installed_list() { run_gext list 2>/dev/null || true; }

# Everything installed, one UUID per line: gext's list plus the shell's own view,
# which also sees system extensions and anything installed outside gext (Gradia
# Capture is built from source and installed with `gnome-extensions install`).
installed_extensions() {
  {
    gext_installed_list
    as_user gnome-extensions list 2>/dev/null || true
  } | grep -v '^[[:space:]]*$' || true
}

# True when the managed set is not fully installed *and enabled* right now.
state_incomplete() {
  local installed="$1" enabled="$2" entry uuid
  for entry in "${entries[@]}"; do
    uuid="${entry#*:}"
    [[ -n "$uuid" ]] || continue
    grep -qF "$uuid" <<<"$installed" || return 0
    # An extension GNOME disabled (shell upgrade, "Extensions" app, or a failed
    # first login) is installed but does nothing — the user sees "no extensions".
    grep -qxF "$uuid" <<<"$enabled" || return 0
  done
  return 1
}

# Versioned gate. The token is a hash of packages.bash (plus packages.local.bash
# for the personal set), which is where the extension lists live: as long as they
# do not change, this mode has nothing new to install, and gext talks to
# extensions.gnome.org on every call — by far the slowest step in the setup. `--force` re-runs it, e.g. after
# you disable an extension by hand and want the managed set back.
# shellcheck source=/dev/null
source "$real_home/.local/share/ucli/scripts/lib/version-script.sh"
gate_name="gnome-extensions-$mode"
gate_version="$(vs_hash "$real_home/.config/ucli/packages.bash")"
# The personal set is defined in the overlay, so its hash is part of the token.
if [[ -r "$personal_file" ]]; then
  gate_version="${gate_version}-$(vs_hash "$personal_file")"
fi
# What this set installs, decided before anything else: an empty personal set
# must not require gext (or a network) to print its note.
entries=()
case "$mode" in
  managed) entries=("${GNOME_MANAGED_EXTENSIONS[@]:-}") ;;
  personal)
    if [[ ! -r "$personal_file" ]]; then
      echo "no ~/.config/ucli/packages.local.bash; nothing personal to install."
      echo "    copy packages.local.bash.example next to it to use this set."
      exit 0
    fi
    entries=("${PERSONAL_GNOME_EXTENSIONS[@]:-}")
    ;;
esac
mapfile -t entries < <(printf '%s\n' "${entries[@]:-}" | awk 'NF')

# --- prune: what left the arrays ---------------------------------------------
# The arrays say what should be installed; the manifest says what this repo put
# there. Without the manifest "removed from the array" could only be guessed, and
# the guess would delete extensions you installed yourself. So: installed-by-us
# minus wanted-now = remove. Both modes read the same manifest and the same
# wanted-union, because `managed` and `personal` are two invocations of one
# script and a per-mode view would let each prune the other's extensions.
state_dir="${XDG_STATE_HOME:-$real_home/.local/state}/ucli"
manifest_file="$state_dir/gnome-extensions.installed"
gradia_uuid="gradia-integration@alexandervanhee.github.io"

wanted_uuids() {
  local entry
  # `${arr[@]:-}` on an empty array still yields one empty element, so filter
  # (plain `if`, not `cond && cmd`: a false trailing condition would make the
  # pipeline return 1 and `set -e` would kill the script).
  local -a managed=() personal=()
  for entry in "${GNOME_MANAGED_EXTENSIONS[@]:-}"; do
    if [[ -n "$entry" ]]; then managed+=("$entry"); fi
  done
  for entry in "${PERSONAL_GNOME_EXTENSIONS[@]:-}"; do
    if [[ -n "$entry" ]]; then personal+=("$entry"); fi
  done

  {
    for entry in "${managed[@]:-}"; do
      if [[ -n "$entry" ]]; then printf '%s\n' "${entry#*:}"; fi
    done
    for entry in "${personal[@]:-}"; do
      if [[ -n "$entry" ]]; then printf '%s\n' "${entry#*:}"; fi
    done
    # Gradia Capture has no PK line to delete, so it follows the managed set:
    # present while that set has entries, gone when you retire the set.
    if (( ${#managed[@]} )); then printf '%s\n' "$gradia_uuid"; fi
  } | sort -u
}

# Record what this run owns. Called after the set is complete, and from the
# "unchanged" fast path, and only ever for what is really installed.
manifest_write() {
  local installed="$1" uuid
  local -a list=()
  while IFS= read -r uuid; do
    [[ -n "$uuid" ]] || continue
    if grep -qF "$uuid" <<<"$installed"; then
      list+=("$uuid")
    fi
  done < <(wanted_uuids)
  ((${#list[@]})) || return 0
  as_user mkdir -p "$state_dir"
  printf '%s\n' "${list[@]}" | as_user tee "$manifest_file" >/dev/null
}

prune_dropped() {
  [[ -s "$manifest_file" ]] || return 0

  local -a recorded=() stale=()
  mapfile -t recorded < "$manifest_file"
  local wanted uuid
  wanted="$(wanted_uuids)"
  for uuid in "${recorded[@]}"; do
    [[ -n "$uuid" ]] || continue
    grep -qxF "$uuid" <<<"$wanted" || stale+=("$uuid")
  done
  ((${#stale[@]})) || return 0

  echo "prune: no longer in the managed or personal set:"
  printf '  - %s\n' "${stale[@]}"
  disable_uuids "${stale[@]}"
  for uuid in "${stale[@]}"; do
    if [[ -d "$real_home/.local/share/gnome-shell/extensions/$uuid" ]]; then
      if as_user gnome-extensions uninstall "$uuid" >/dev/null 2>&1; then
        echo "  removed $uuid (user extension)"
      else
        echo "warning: could not uninstall $uuid; remove it in Extension Manager" >&2
      fi
    elif [[ -d "/usr/share/gnome-shell/extensions/$uuid" ]]; then
      echo "  $uuid is a system extension: disabled, files left to pacman"
    else
      echo "  $uuid was already gone; dropped its enabled entry"
    fi
  done

  # Forget what was just pruned, so it is not reported as "already gone" on every
  # later run. What is still installed stays recorded; the install tail re-records
  # the wanted set when it runs.
  local -a keep=()
  local other drop
  for uuid in "${recorded[@]}"; do
    if [[ -z "$uuid" ]]; then continue; fi
    drop=0
    for other in "${stale[@]}"; do
      if [[ "$uuid" == "$other" ]]; then drop=1; fi
    done
    if (( ! drop )); then keep+=("$uuid"); fi
  done
  if (( ${#keep[@]} )); then
    printf '%s\n' "${keep[@]}" | as_user tee "$manifest_file" >/dev/null
  else
    as_user rm -f "$manifest_file"
  fi
}
prune_dropped

# Checked after the prune on purpose: emptying the array is how you retire an
# extension, and that must still clean up what the last run installed.
if (( ${#entries[@]} == 0 )); then
  echo "GNOME extension set '$mode' is empty; nothing to install."
  exit 0
fi

if ! command -v gext >/dev/null 2>&1; then
  echo "gext (gnome-extensions-cli) not found" >&2
  echo "  run: ucli install-gnome-extensions-cli" >&2
  exit 1
fi

if ((!force)) && ! vs_check "$gate_name" user "$gate_version"; then
  if state_incomplete "$(installed_extensions)" "$(enabled_extensions || true)"; then
    echo "GNOME extension set '$mode' is recorded as done but is not installed/enabled; re-applying."
  else
    echo "GNOME extension set '$mode' unchanged since the last run (${gate_version}); skipping."
    echo "    re-run with --force to apply it anyway: ucli setup-extensions --force"
    # Nothing to install, but the manifest may predate this run (or this script):
    # record the wanted set that is actually installed, so the next removal from
    # the arrays has something to prune against.
    manifest_write "$(installed_extensions)"
    exit 0
  fi
fi

# Machines set up before user-theme moved to extensions.gnome.org still carry
# gnome-shell-extensions: fourteen classic extensions (apps-menu, window-list,
# status-icons, system-monitor, …) that nobody asked for, most of them only ever
# active in the GNOME Classic session, plus a dormant copy of user-theme. Nothing
# breaks while it is there — but it is the bulk of the "System Extensions" list, so
# say how to get rid of it instead of leaving it as a mystery.
if [[ "$mode" == managed ]] && command -v pacman >/dev/null 2>&1 \
   && pacman -Q gnome-shell-extensions >/dev/null 2>&1; then
  echo "note: gnome-shell-extensions is installed (14 classic extensions, incl. a"
  echo "      dormant user-theme). user-theme now comes from extensions.gnome.org,"
  echo "      so the package is not needed: sudo pacman -Rns gnome-shell-extensions"
fi

# Gradia Capture is part of the managed set but is not a gext entry: no
# extensions.gnome.org listing and no Arch package, so it is built from its pinned
# upstream commit and installed with `gnome-extensions install`. Its UUID is added
# to the same single write below; if the build fails the set is incomplete rather
# than quietly one extension short.
gradia_ok=0
if [[ "$mode" == managed ]]; then
  gradia_args=()
  ((force)) && gradia_args=(--force)
  if [[ -x "$script_dir/install-gradia-capture.sh" ]]; then
    if "$script_dir/install-gradia-capture.sh" ${gradia_args[@]+"${gradia_args[@]}"}; then
      gradia_ok=1
    fi
  else
    echo "warning: install-gradia-capture.sh not found; run 'ucli chezmoi-apply'" >&2
  fi
fi

echo "GNOME extension set '$mode' ..."
uuids=()
failed=()
for entry in "${entries[@]}"; do
  pk="${entry%%:*}"
  uuid="${entry#*:}"
  if install_extension_by_pk "$pk" "$uuid"; then
    [[ -n "$uuid" ]] && uuids+=("$uuid")
  else
    failed+=("${uuid:-pk=$pk}")
  fi
done

if [[ "$mode" == managed ]]; then
  if ((gradia_ok)); then
    uuids+=("$gradia_uuid")
  else
    failed+=("$gradia_uuid (build failed)")
  fi
fi

# Enable only what is really there: pushing the uuid of a failed download into
# enabled-extensions makes GNOME list an extension it cannot load.
enable_uuids "${uuids[@]}"

# Verify the end state. The gate is committed only when everything is installed
# AND enabled, so a failed run is retried instead of being remembered as done.
installed_now="$(installed_extensions)"
enabled_now="$(enabled_extensions || true)"
missing=()
for uuid in "${uuids[@]}"; do
  grep -qF "$uuid" <<<"$installed_now" || missing+=("$uuid (not installed)")
  grep -qxF "$uuid" <<<"$enabled_now" || missing+=("$uuid (not enabled)")
done

total=$(( ${#uuids[@]} + ${#failed[@]} ))
# Count what is really there, not what we tried to install: an extension that was
# "installed" but is absent from the shell's own list is still a miss.
installed_count=0
for uuid in "${uuids[@]}"; do
  if grep -qF "$uuid" <<<"$installed_now"; then
    installed_count=$((installed_count + 1))
  fi
done
if (( ${#failed[@]} || ${#missing[@]} )); then
  {
    echo
    echo "warning: GNOME extension set '$mode' is incomplete ($installed_count of $total installed)"
    for line in "${failed[@]:-}" "${missing[@]:-}"; do
      if [[ -n "$line" ]]; then
        echo "  - $line"
      fi
    done
    echo "  nothing was recorded as done, so this runs again next time:"
    echo "    ucli setup-extensions --force"
    echo "    (if gext itself is the problem: ucli install-gnome-extensions-cli)"
  } >&2
  exit 1
fi

manifest_write "$installed_now"
vs_commit "$gate_name" user "$gate_version"
echo "done: ${#uuids[@]} extension(s) installed and enabled."
echo "      log out and back in (or restart GNOME Shell) to load them."
