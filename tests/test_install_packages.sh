#!/usr/bin/env bash
# install-packages.sh: what each mode selects for a distro/CPU/GPU/desktop,
# how names resolve (repo, group, AUR), the installer-owned skips on CachyOS,
# and the exact pacman / AUR helper / systemctl calls.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

pkgs() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-packages.sh "$@" ); }

# world — every array holds a recognisable name; repo-* resolve in pacman,
# grp-* is a group of two, aur-* exist only in the AUR.
world() {
  stub pacman 'case $1 in
    -Si)  [[ $2 == repo-* ]] ;;
    -Sgq) [[ $2 == grp-* ]] && printf "%s-a\n%s-b\n" "$2" "$2" ;;
    *)    exit 0 ;;
  esac'
  # only the AUR lookups (`python3 - <pkg>`) are faked; chezmoi data parsing is real
  local py; py="$(PATH=/usr/bin:/bin command -v python3)"
  stub python3 "if [[ \$1 == - ]]; then [[ \$2 == aur-* ]]; else exec $py \"\$@\"; fi"
  stub sudo '"$@"'
  stub systemctl 'case $1 in list-unit-files) [[ $2 == repo-gdm.service ]] ;; esac; exit 0'
  t_config_file packages.bash <<'PKG'
BOOTSTRAP=(repo-git)
UCLI_RUNTIME=(repo-gum)
CPU_INTEL=(repo-intel-ucode)
CPU_AMD=(repo-amd-ucode)
GPU_AMD=(repo-mesa)
GPU_INTEL=(repo-intel-media)
GPU_NVIDIA=(repo-nvidia)
SYSTEM_CORE_TOOLS=(repo-htop)
SYSTEM_QOL_TOOLS=()
SYSTEM_SUPPORT=()
BOOT_SUPPORT=(repo-efibootmgr)
SYSTEM_MEDIA_CODECS=(grp-gst)
HARDWARE_FINGERPRINT=(repo-fprintd)
HARDWARE_TOUCHPAD=(repo-libinput-tools)
FONTS_THEMES=(repo-noto)
DESKTOP_GNOME_BASE=(repo-gnome)
GNOME_SYSTEM_EXTENSION_PACKAGES=(repo-caffeine)
GNOME_EXTENSION_TOOLING=(repo-extension-manager)
SERVICES_GNOME=(repo-gdm)
DESKTOP_TERMINAL_GNOME=(repo-ghostty)
DESKTOP_TERMINAL_KDE=(aur-kwi)
DESKTOP_KDE_BASE=(repo-plasma)
DESKTOP_KDE_ADDITIONS=()
SERVICES_KDE=(repo-sddm)
DESKTOP_BROWSER=(repo-firefox)
MANUAL_AUR=(aur-shelly)
APPS=(repo-mpv)
DEV_CLI=(repo-jq)
DEV=(repo-docker)
GAMING=(repo-steam)
PERSONAL_PKGS=()
PERSONAL_DEV=()
DESKTOP_REMOVE_GNOME=(repo-epiphany repo-yelp)
DESKTOP_REMOVE_KDE=(repo-kate)
PKG
}

field() { sed -n "s/^$1: //p" <<<"$T_OUT"; }

test_base_on_arch_follows_the_hardware() {
  world
  t_run pkgs --dry-run --distro=arch --cpu=intel --gpu=amd base
  assert_status 0
  # hardware mode probes the real machine, so check membership, not the exact list
  local p
  for p in repo-gum repo-git repo-intel-ucode repo-mesa repo-htop repo-efibootmgr grp-gst repo-noto; do
    assert_contains " $(field 'selected packages') " " $p "
  done
  assert_not_contains "$(field 'selected packages')" "repo-amd-ucode"
  assert_contains "$(field 'repo packages')" "grp-gst-a grp-gst-b"
  assert_eq "(none)" "$(field 'missing packages')"
}

test_cachyos_leaves_installer_owned_parts_alone() {
  world
  t_run pkgs --dry-run --distro=cachyos --cpu=intel --gpu=nvidia base
  assert_status 0
  assert_not_contains "$(field 'selected packages')" "ucode"
  assert_not_contains "$(field 'selected packages')" "repo-nvidia"
  assert_not_contains "$(field 'selected packages')" "efibootmgr"
  assert_contains "$T_OUT" "GPU setup is handled by chwd"
}

test_desktop_base_is_skipped_on_cachyos_unless_asked() {
  world
  t_run pkgs --dry-run --distro=cachyos --desktop=gnome desktop
  assert_not_contains "$(field 'selected packages')" "repo-gnome "
  assert_contains "$(field 'selected packages')" "repo-ghostty"
  t_run pkgs --dry-run --distro=cachyos --desktop=gnome --base-desktop desktop
  assert_contains "$(field 'selected packages')" "repo-gnome"
  assert_eq "repo-gdm" "$(field services)"
}

test_dev_and_gaming_need_the_role_or_force() {
  world
  stub chezmoi 'echo "{\"role\": \"minimal\", \"gaming\": false}"'
  t_run pkgs --dry-run --distro=arch dev
  assert_contains "$T_OUT" "role='minimal' is not dev; skipping"
  t_run pkgs --dry-run --distro=arch --force dev
  assert_eq "repo-jq repo-docker" "$(field 'selected packages')"
  t_run pkgs --dry-run --distro=arch gaming
  assert_eq "(none)" "$(field 'selected packages')"
}

test_aur_names_resolve_and_unknown_names_fail() {
  world
  t_run pkgs --dry-run --distro=arch --desktop=kde apps
  assert_status 0
  assert_eq "aur-kwi aur-shelly" "$(field 'aur packages')"
  echo 'APPS=(repo-mpv no-such-thing)' >>"$HOME/.config/ucli/packages.bash"
  t_run pkgs --dry-run --distro=arch apps
  assert_status 1
  assert_eq "no-such-thing" "$(field 'missing packages')"
}

test_a_real_run_installs_repo_then_aur_and_enables_services() {
  world
  S="$(t_deployed install/install-packages)"
  t_fake_script "${S%/*}/install-aur-helper.sh" 'echo paru'
  stub paru
  t_run bash "$S" --yes --distro=arch --desktop=gnome --base-desktop desktop
  assert_status 0
  assert_called "pacman -S --needed --ignore=repo-epiphany,repo-yelp --noconfirm repo-gnome"
  assert_called "install-aur-helper.sh --yes"
  assert_called "paru -S --needed --noconfirm aur-shelly"
  assert_called "systemctl enable repo-gdm.service"
}

test_plasma_uses_the_kde_removal_list() {
  world
  S="$(t_deployed install/install-packages)"
  t_fake_script "${S%/*}/install-aur-helper.sh" 'echo shelly'
  stub shelly
  t_run bash "$S" --yes --distro=arch --desktop=plasma --base-desktop desktop
  assert_status 0
  assert_called "--ignore=repo-kate"
  assert_called "shelly install aur aur-kwi --needed --no-confirm"
}

test_no_aur_helper_is_an_error_not_a_skip() {
  world
  S="$(t_deployed install/install-packages)"
  t_fake_script "${S%/*}/install-aur-helper.sh" 'echo none'
  t_run bash "$S" --yes --distro=arch --desktop=kde apps
  assert_status 1
  assert_contains "$T_OUT" "no AUR helper available; cannot install: aur-kwi aur-shelly"
}

test_arguments() {
  world
  t_run pkgs --dry-run --distro=ubuntu base
  assert_status 1
  assert_contains "$T_OUT" "Unsupported distro: ubuntu"
  t_run pkgs --dry-run --distro=arch sideways
  assert_status 2
  t_run pkgs
  assert_status 2
}

t_main
