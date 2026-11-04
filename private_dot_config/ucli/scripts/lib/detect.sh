#!/usr/bin/env bash
# Shared detection helpers for ucli scripts.

ucli_norm() {
  tr '[:upper:]' '[:lower:]' <<<"${1:-}" | tr - _
}

ucli_profile_value() {
  local key="$1" fallback="${2:-}"
  if command -v chezmoi >/dev/null 2>&1; then
    chezmoi data 2>/dev/null | python3 -c 'import json,sys; k=sys.argv[1]; f=sys.argv[2];
try:
    d=json.load(sys.stdin)
except Exception:
    print(f); raise SystemExit(0)
v=d.get(k, f)
print(f if v is None else v)' "$key" "$fallback" 2>/dev/null || printf '%s\n' "$fallback"
  else
    printf '%s\n' "$fallback"
  fi
}

detect_distro_raw() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "${ID:-unknown}"
  else
    printf 'unknown\n'
  fi
}

# ID_LIKE from /etc/os-release. Arch and CachyOS both ship /etc/os-release (a
# symlink to /usr/lib/os-release) and the same pacman layout; every Arch
# derivative that sets ID_LIKE=arch (EndeavourOS, Garuda, Arco, Artix, …) does too.
detect_distro_like() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "${ID_LIKE:-}"
  else
    printf ''
  fi
}

# Everything this repo assumes (pacman, /etc/snapper, mkinitcpio, limine) is
# inherited from Arch, so the family is what matters, not the branding.
detect_distro_family() {
  local id like
  id="$(ucli_norm "$(detect_distro_raw)")"
  like="$(ucli_norm "$(detect_distro_like)")"
  case "$id" in
    arch|archlinux|cachyos) printf 'arch\n'; return 0 ;;
  esac
  case " $like " in
    *" arch "*) printf 'arch\n'; return 0 ;;
  esac
  printf '%s\n' "$id"
}

detect_distro() {
  local override
  override="$(ucli_profile_value distro "")"
  override="$(ucli_norm "$override")"
  if [[ -n "$override" && "$override" != auto ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  ucli_norm "$(detect_distro_raw)"
}

detect_arch() {
  if command -v chezmoi >/dev/null 2>&1; then
    chezmoi data 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("chezmoi",{}).get("arch",""))' 2>/dev/null && return 0
  fi
  uname -m
}

detect_cpu() {
  local override
  override="$(ucli_profile_value cpu "")"
  override="$(ucli_norm "$override")"
  if [[ -n "$override" && "$override" != auto ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if grep -qi 'GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    printf 'intel\n'
  elif grep -qi 'AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
    printf 'amd\n'
  else
    printf 'unknown\n'
  fi
}

detect_gpu() {
  local override
  override="$(ucli_profile_value gpu "")"
  override="$(ucli_norm "$override")"

  if [[ -n "$override" && "$override" != auto ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  # Prefer sysfs vendor IDs. No extra package needed.
  # AMD:    0x1002
  # Intel:  0x8086
  # NVIDIA: 0x10de
  local vendors=""
  vendors="$(cat /sys/class/drm/card*/device/vendor 2>/dev/null | sort -u || true)"

  if grep -qi '0x1002' <<<"$vendors"; then
    printf 'amd\n'
    return 0
  fi

  if grep -qi '0x10de' <<<"$vendors"; then
    printf 'nvidia\n'
    return 0
  fi

  if grep -qi '0x8086' <<<"$vendors"; then
    printf 'intel\n'
    return 0
  fi

  # Fallback to lspci if available.
  if command -v lspci >/dev/null 2>&1; then
    local gpu_lines
    gpu_lines="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"

    if grep -qi 'AMD\|ATI\|Advanced Micro Devices' <<<"$gpu_lines"; then
      printf 'amd\n'
      return 0
    fi

    if grep -qi 'NVIDIA' <<<"$gpu_lines"; then
      printf 'nvidia\n'
      return 0
    fi

    if grep -qi 'Intel' <<<"$gpu_lines"; then
      printf 'intel\n'
      return 0
    fi
  fi

  printf 'unknown\n'
}

detect_machine() {
  local configured
  configured="$(ucli_norm "$(ucli_profile_value machine auto)")"
  if [[ -n "$configured" && "$configured" != auto ]]; then
    printf '%s\n' "$configured"
    return 0
  fi
  if grep -Rqs '^Battery$' /sys/class/power_supply/*/type 2>/dev/null; then
    printf 'laptop\n'
  else
    printf 'workstation\n'
  fi
}

detect_virtualization() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt 2>/dev/null || printf 'none\n'
  else
    printf 'unknown\n'
  fi
}

detect_desktop_session() {
  local value="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
  value="$(ucli_norm "$value")"
  case "$value" in
    *gnome*) printf 'gnome\n' ;;
    *kde*|*plasma*) printf 'kde\n' ;;
    *hyprland*) printf 'hyprland\n' ;;
    *) printf '%s\n' "${value:-none}" ;;
  esac
}

detect_installed_desktop() {
  local found=()
  pacman -Q gnome-shell >/dev/null 2>&1 && found+=(gnome)
  { pacman -Q plasma-desktop >/dev/null 2>&1 || pacman -Q plasma-meta >/dev/null 2>&1; } && found+=(kde)
  pacman -Q hyprland >/dev/null 2>&1 && found+=(hyprland)
  if ((${#found[@]} == 1)); then
    printf '%s\n' "${found[0]}"
  elif ((${#found[@]} == 0)); then
    printf 'none\n'
  else
    printf 'ambiguous:%s\n' "${found[*]}"
    return 1
  fi
}

detect_desktop() {
  local configured session installed
  configured="$(ucli_norm "$(ucli_profile_value desktop auto)")"
  if [[ -n "$configured" && "$configured" != auto ]]; then
    printf '%s\n' "$configured"
    return 0
  fi
  session="$(detect_desktop_session)"
  if [[ -n "$session" && "$session" != none ]]; then
    printf '%s\n' "$session"
    return 0
  fi
  installed="$(detect_installed_desktop 2>/dev/null || true)"
  if [[ -n "$installed" && "$installed" != none && "$installed" != ambiguous:* ]]; then
    printf '%s\n' "$installed"
    return 0
  fi
  printf 'none\n'
  return 1
}

detect_terminal() {
  local configured desktop
  configured="$(ucli_norm "$(ucli_profile_value terminal auto)")"
  if [[ -n "$configured" && "$configured" != auto ]]; then
    printf '%s\n' "$configured"
    return 0
  fi
  desktop="$(detect_desktop 2>/dev/null || echo none)"
  # Same rule as DESKTOP_TERMINAL_<DE> in packages.bash: ghostty on GNOME and
  # Hyprland (GTK4/Wayland), kwi on Plasma (KDE's new Qt Quick terminal, also
  # built on libghostty-vt).
  case "$desktop" in
    gnome|hyprland) printf 'ghostty\n' ;;
    kde|plasma) printf 'kwi\n' ;;
    *) printf 'none\n' ;;
  esac
}

detect_role() {
  ucli_norm "$(ucli_profile_value role dev)"
}

detect_gaming() {
  ucli_norm "$(ucli_profile_value gaming false)"
}

detect_root_fstype() {
  findmnt -no FSTYPE / 2>/dev/null || printf 'unknown\n'
}

detect_root_source() {
  findmnt -no SOURCE / 2>/dev/null || printf 'unknown\n'
}

detect_root_options() {
  findmnt -no OPTIONS / 2>/dev/null || printf 'unknown\n'
}

detect_btrfs_layout() {
  if [[ "$(detect_root_fstype)" != btrfs ]]; then
    printf 'not-btrfs\n'
    return 1
  fi
  local subvols missing=()
  subvols="$(btrfs subvolume list / 2>/dev/null || true)"
  for required in '@' '@home' '@log' '@pkg'; do
    grep -Eq " path ${required}$" <<<"$subvols" || missing+=("$required")
  done
  if ((${#missing[@]})); then
    printf 'missing:%s\n' "${missing[*]}"
    return 1
  fi
  printf 'ok\n'
}

detect_snapper_root() {
  [[ -f /etc/snapper/configs/root ]] && printf 'ok\n' || { printf 'missing\n'; return 1; }
}

detect_limine() {
  command -v limine-update >/dev/null 2>&1 && printf 'ok\n' || { printf 'missing\n'; return 1; }
}
