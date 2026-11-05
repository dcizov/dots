#!/usr/bin/env bash
set -euo pipefail

# Quiet boot: plymouth + the kernel parameters this repo wants, appended to
# whatever the bootloader already has.
#
# Why this exists: on Arch, "quiet boot" is not a package. pacman installs
# plymouth and the kernel keeps printing 200 lines of dmesg over the splash until
# you also (a) add the plymouth hook to the initramfs, (b) put `splash` (and
# normally `quiet`) on the kernel command line, and (c) rebuild both the initramfs
# and the boot entries. CachyOS' installer does that for you; archinstall does
# not, and limine has no /etc/default/grub to edit — its command line lives in
# /etc/default/limine (limine-mkinitcpio-hook) or inside limine.conf itself.
#
# So this script is the "append parameters" step, once, for every layout:
#
#   /etc/default/limine            limine-mkinitcpio-hook / CachyOS. KERNEL_CMDLINE[default]
#                                  is the source; limine-update rewrites limine.conf.
#   limine.conf (archinstall)      entries carry `cmdline:` lines; they are edited in place.
#   /etc/kernel/cmdline            Unified Kernel Images (mkinitcpio/ukify) bake it in.
#
# What it never does: replace a command line, remove a parameter, or touch
# BOOT_ORDER. It adds the tokens from KERNEL_CMDLINE_EXTRA (packages.bash) that
# are missing, and reports the ones that were already there.
#
# Scope: limine only. GRUB's /etc/default/grub and systemd-boot's per-entry files
# are installer-owned in the layouts this repo targets, and guessing at them is
# how a boot breaks; the script says what it found and stops.

yes_flag=0
dry_run=0
with_plymouth=1
force=0
usage() {
  cat <<'USAGE'
usage: sudo setup-boot.sh [--yes] [--dry-run] [--no-plymouth] [--force]

Append this machine's kernel parameters (KERNEL_CMDLINE_EXTRA in packages.bash)
to limine, and install/configure plymouth so the boot is quiet.

  --yes           non-interactive (pacman --noconfirm)
  --dry-run       print every change, write nothing
  --no-plymouth   do not install plymouth and do not add `splash`
  --force         rebuild the initramfs even when nothing changed
USAGE
}
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --dry-run|-n) dry_run=1 ;;
    --no-plymouth) with_plymouth=0 ;;
    --force) force=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

# Test seam: prefix for every system path (/etc, /boot). Empty on a real machine.
root="${UCLI_ETC_ROOT:-}"

if [[ "${EUID:-$(id -u)}" -ne 0 && -z "$root" ]]; then
  echo "Run as root: sudo ucli setup-boot" >&2
  exit 1
fi

run() {
  printf '+ %q ' "$@"; echo
  if (( ! dry_run )) && [[ -z "${UCLI_DRY_RUN_ONLY:-}" ]]; then "$@"; fi
}

changed=0

# ---------------------------------------------------------------- configuration
# The tokens and the theme come from the same file as everything else this
# machine gets. Read them out of the invoking user's home: sudo runs us as root.
real_user="${SUDO_USER:-$USER}"
if [[ -n "$root" ]]; then
  # Test seam: with UCLI_ETC_ROOT set the config comes from $HOME, not the passwd
  # database, so a fake tree can be exercised without touching the real machine.
  real_home="${HOME:-}"
else
  real_home="$(getent passwd "$real_user" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "$real_home" ]] || real_home="${HOME:-}"
fi
if [[ -z "$real_home" ]]; then
  echo "warning: cannot resolve $real_user's home; using KERNEL_CMDLINE_EXTRA's defaults" >&2
fi
for cfg in "$real_home/.config/ucli/packages.bash" "$real_home/.config/ucli/packages.local.bash"; do
  [[ -n "$real_home" && -r "$cfg" ]] || continue
  # shellcheck source=/dev/null
  . "$cfg"
done
KERNEL_CMDLINE_EXTRA=("${KERNEL_CMDLINE_EXTRA[@]:-}")
PLYMOUTH_THEME="${PLYMOUTH_THEME:-}"

tokens=()
for tok in "${KERNEL_CMDLINE_EXTRA[@]:-}"; do
  [[ -n "$tok" ]] && tokens+=("$tok")
done

# `splash` without plymouth is a no-op kernel parameter at best.
if (( ! with_plymouth )) && command -v plymouth >/dev/null 2>&1; then
  : # plymouth is installed: keep splash even though we are not managing it now
elif (( ! with_plymouth )); then
  kept=()
  for tok in ${tokens[@]+"${tokens[@]}"}; do
    [[ "$tok" == splash ]] || kept+=("$tok")
  done
  tokens=(${kept[@]+"${kept[@]}"})
fi

if ((${#tokens[@]} == 0)) && (( ! with_plymouth )); then
  echo "nothing to do: no kernel parameters configured and --no-plymouth given"
  exit 0
fi

echo "kernel parameters: ${tokens[*]:-<none>}"

# ------------------------------------------------------------------- bootloader
conf_files=()
while IFS= read -r f; do conf_files+=("$f"); done < <(
  for f in \
    "${root}/boot/limine.conf" \
    "${root}/boot/limine/limine.conf" \
    "${root}/boot/EFI/arch-limine/limine.conf" \
    "${root}/efi/EFI/arch-limine/limine.conf" \
    "${root}/efi/limine.conf" \
    "${root}/boot/EFI/limine/limine.conf" \
    "${root}/boot/EFI/BOOT/limine.conf"; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
)

default_file="${root}/etc/default/limine"
kernel_cmdline_file="${root}/etc/kernel/cmdline"
[[ -f "$default_file" ]] || default_file=""
[[ -f "$kernel_cmdline_file" ]] || kernel_cmdline_file=""

if [[ -z "$default_file" ]] && ((${#conf_files[@]} == 0)) && [[ -z "$kernel_cmdline_file" ]]; then
  cat >&2 <<'EOF'
no limine configuration found. Looked for:

  /etc/default/limine                       (limine-mkinitcpio-hook, CachyOS)
  /boot/limine.conf                         (limine on /boot)
  /boot/limine/limine.conf                  (archinstall, BIOS)
  /boot/EFI/arch-limine/limine.conf         (archinstall, UEFI)
  /efi/EFI/arch-limine/limine.conf          (archinstall, UEFI, /efi mount)
  /etc/kernel/cmdline                       (Unified Kernel Image)

This step only knows limine. GRUB (/etc/default/grub + grub-mkconfig) and
systemd-boot are left alone on purpose: neither is what `ucli setup-snapshots`
sets up, and rewriting a bootloader's entries from a dotfiles step is how a
machine stops booting. Tell me which one you use and it can be added.
EOF
  exit 1
fi

# Rebuild the initramfs once, at the end, if anything actually changed.
need_initramfs=0

# ---------------------------------------------------------------- plymouth setup
plymouth_installed=0
command -v plymouth >/dev/null 2>&1 && plymouth_installed=1

if (( with_plymouth )) && (( ! plymouth_installed )); then
  if command -v pacman >/dev/null 2>&1; then
    echo "installing plymouth ..."
    if (( yes_flag )); then
      run pacman -S --needed --noconfirm plymouth
    else
      run pacman -S --needed plymouth
    fi
    if (( ! dry_run )); then
      command -v plymouth >/dev/null 2>&1 && plymouth_installed=1
      (( plymouth_installed )) && changed=1
    fi
  else
    echo "warning: pacman not found; install plymouth yourself" >&2
  fi
elif (( with_plymouth )) && (( plymouth_installed )); then
  echo "plymouth: already installed"
fi

mkinitcpio_conf="${root}/etc/mkinitcpio.conf"
if (( with_plymouth )) && [[ -f "$mkinitcpio_conf" ]]; then
  # plymouth must be in the initramfs. Order (ArchWiki): after `systemd` when that
  # hook is used, and before `encrypt`/`sd-encrypt` so the splash covers the LUKS
  # prompt instead of appearing after it.
  if (( dry_run )); then
    echo "+ would ensure the plymouth hook in $mkinitcpio_conf"
  else
    if hook_out="$(python3 - "$mkinitcpio_conf" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()
out = []
found = False
changed = False

for line in lines:
    if not line.strip().startswith("HOOKS="):
        out.append(line)
        continue
    found = True
    inner = line.split("=", 1)[1].strip()
    inner = inner.strip("()")
    hooks = [h for h in inner.split() if h]
    if "plymouth" in hooks:
        out.append(line)
        continue
    # Insert before the first encryption hook, else after `systemd`, else last.
    insert_at = len(hooks)
    for i, hook in enumerate(hooks):
        if hook in ("encrypt", "sd-encrypt"):
            insert_at = i
            break
    else:
        if "systemd" in hooks:
            insert_at = hooks.index("systemd") + 1
    hooks.insert(insert_at, "plymouth")
    out.append("HOOKS=(" + " ".join(hooks) + ")")
    changed = True

if not found:
    print("no HOOKS= line in mkinitcpio.conf", file=sys.stderr)
    sys.exit(2)

if changed:
    path.write_text("\n".join(out) + "\n")
    print("hook added")
else:
    print("hook already present")
PY
)"; then
      echo "initramfs: $hook_out"
      if [[ "$hook_out" == "hook added" ]]; then
        changed=1
        need_initramfs=1
      fi
    else
      echo "warning: could not edit $mkinitcpio_conf; add the plymouth hook to HOOKS yourself" >&2
    fi
  fi
fi

plymouth_conf="${root}/etc/plymouth/plymouthd.conf"
if (( with_plymouth )) && (( ! plymouth_installed )) && (( ! dry_run )); then
  echo "warning: plymouth is not installed; skipping $plymouth_conf" >&2
fi
if (( with_plymouth )) && (( plymouth_installed || dry_run )); then
  desired_theme="$PLYMOUTH_THEME"
  if (( dry_run )); then
    echo "+ would set ShowDelay=0${desired_theme:+ and Theme=$desired_theme} in $plymouth_conf"
  else
    mkdir -p "$(dirname "$plymouth_conf")"
    if [[ ! -f "$plymouth_conf" ]]; then
      {
        echo "[Daemon]"
        echo "# Written by ucli setup-boot. plymouth's own default theme is used"
        echo "# unless PLYMOUTH_THEME is set in packages.bash."
        echo "ShowDelay=0"
        [[ -n "$desired_theme" ]] && echo "Theme=$desired_theme"
      } >"$plymouth_conf"
      echo "wrote $plymouth_conf"
      changed=1
      need_initramfs=1
    else
      # Keep whatever else is in the file; only touch what we own.
      current_theme="$(sed -n 's/^Theme=//p' "$plymouth_conf" | tail -1)"
      if [[ -n "$desired_theme" && "$current_theme" != "$desired_theme" ]]; then
        if grep -q '^Theme=' "$plymouth_conf"; then
          sed -i "s|^Theme=.*|Theme=$desired_theme|" "$plymouth_conf"
        else
          printf 'Theme=%s\n' "$desired_theme" >>"$plymouth_conf"
        fi
        echo "plymouth theme: ${current_theme:-<default>} -> $desired_theme"
        changed=1
        need_initramfs=1
      elif [[ -n "$desired_theme" ]]; then
        echo "plymouth theme: already $desired_theme"
      else
        echo "plymouth theme: ${current_theme:-<plymouth default>} (PLYMOUTH_THEME unset)"
      fi
      if ! grep -q '^ShowDelay=' "$plymouth_conf"; then
        sed -i "/^\[Daemon\]/a ShowDelay=0" "$plymouth_conf"
        echo "plymouth: ShowDelay=0 added"
        changed=1
      fi
    fi
  fi
fi

# ------------------------------------------------------- kernel command line(s)
# Missing tokens, in the order they are configured.
missing_from() {
  local current="$1"
  local tok
  for tok in ${tokens[@]+"${tokens[@]}"}; do
    case " $current " in
      *" $tok "*) ;;
      *) printf '%s\n' "$tok" ;;
    esac
  done
}

if [[ -n "$default_file" ]]; then
  existing="$(sed -n 's/^KERNEL_CMDLINE\[default\][+]*="\(.*\)"$/\1/p' "$default_file" | tr '\n' ' ')"
  missing="$(missing_from "$existing" | tr '\n' ' ')"
  missing="${missing% }"
  if [[ -z "$existing" ]]; then
    echo "warning: $default_file has no KERNEL_CMDLINE[default] line; leaving it alone" >&2
    echo "         add one, then re-run: KERNEL_CMDLINE[default]=\"root=... rw\"" >&2
  elif [[ -z "$missing" ]]; then
    echo "kernel cmdline: $default_file already has everything (${tokens[*]:-})"
  else
    echo "kernel cmdline: adding '$missing' to $default_file"
    if (( dry_run )); then
      echo "+ would append KERNEL_CMDLINE[default]+=\" $missing\" to $default_file"
    else
      cp -a "$default_file" "${default_file}.bak.$(date +%F-%H%M%S)"
      # Append after the last KERNEL_CMDLINE[default] line, so a later base line
      # cannot cancel it out.
      python3 - "$default_file" "$missing" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
addition = sys.argv[2]
lines = path.read_text().splitlines()
last = max((i for i, line in enumerate(lines)
            if line.startswith("KERNEL_CMDLINE[default]")), default=None)
entry = f'KERNEL_CMDLINE[default]+=" {addition}"'
if last is None:
    lines.append(entry)
else:
    lines.insert(last + 1, entry)
path.write_text("\n".join(lines) + "\n")
PY
      changed=1
      need_initramfs=1
    fi
  fi
fi

if ((${#conf_files[@]})); then
  for conf in "${conf_files[@]}"; do
    # limine.conf entries: `    cmdline: <params>`. Read all of them, then edit.
    existing="$(sed -n 's/^[[:space:]]*cmdline:[[:space:]]*//p' "$conf" | tr '\n' ' ')"
    if [[ -z "$existing" ]]; then
      echo "note: $conf has no cmdline: lines (Unified Kernel Image entries bake"
      echo "      their command line in; see /etc/kernel/cmdline below)"
      continue
    fi
    missing="$(missing_from "$existing" | tr '\n' ' ')"
    missing="${missing% }"
    if [[ -z "$missing" ]]; then
      echo "kernel cmdline: $conf already has everything"
      continue
    fi
    echo "kernel cmdline: adding '$missing' to $conf"
    if (( dry_run )); then
      echo "+ would append '$missing' to each cmdline: line of $conf"
    else
      cp -a "$conf" "${conf}.bak.$(date +%F-%H%M%S)"
      python3 - "$conf" "$missing" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
addition = sys.argv[2].split()
pattern = re.compile(r"^(\s*cmdline:\s*)(.*)$")

out = []
for line in path.read_text().splitlines():
    match = pattern.match(line)
    if not match:
        out.append(line)
        continue
    head, current = match.group(1), match.group(2).rstrip()
    have = set(current.split())
    for token in addition:
        if token not in have:
            current = f"{current} {token}".strip()
            have.add(token)
    out.append(f"{head}{current}")
path.write_text("\n".join(out) + "\n")
PY
      changed=1
    fi
  done
fi

if [[ -n "$kernel_cmdline_file" ]]; then
  existing="$(head -1 "$kernel_cmdline_file")"
  missing="$(missing_from "$existing" | tr '\n' ' ')"
  missing="${missing% }"
  if [[ -z "$missing" ]]; then
    echo "kernel cmdline: $kernel_cmdline_file already has everything"
  else
    echo "kernel cmdline: adding '$missing' to $kernel_cmdline_file (UKI)"
    if (( dry_run )); then
      echo "+ would append '$missing' to $kernel_cmdline_file"
    else
      cp -a "$kernel_cmdline_file" "${kernel_cmdline_file}.bak.$(date +%F-%H%M%S)"
      printf '%s %s\n' "$existing" "$missing" | tr -s ' ' >"$kernel_cmdline_file"
      changed=1
      need_initramfs=1
    fi
  fi
fi

# ------------------------------------------------------------- rebuild + verify
if (( need_initramfs || force )); then
  if [[ -f "$mkinitcpio_conf" ]] && command -v mkinitcpio >/dev/null 2>&1; then
    run mkinitcpio -P
  elif (( ! dry_run )); then
    echo "warning: cannot rebuild the initramfs here (mkinitcpio missing);" >&2
    echo "         run 'sudo mkinitcpio -P' before rebooting" >&2
  fi
fi

if command -v limine-update >/dev/null 2>&1; then
  run limine-update
elif ((${#conf_files[@]})); then
  echo "note: limine.conf is read at boot; no limine-update needed (not installed)"
fi

# Verification, not optimism: read the files back. A dry run wrote nothing, so it
# has nothing to verify.
rc=0
if (( ! dry_run )); then
if [[ -n "$default_file" && -n "$(missing_from "$(sed -n 's/^KERNEL_CMDLINE\[default\][+]*="\(.*\)"$/\1/p' "$default_file" | tr '\n' ' ')" )" ]]; then
  echo "verification failed: $default_file is still missing tokens" >&2
  rc=1
fi
for conf in ${conf_files[@]+"${conf_files[@]}"}; do
  existing="$(sed -n 's/^[[:space:]]*cmdline:[[:space:]]*//p' "$conf" | tr '\n' ' ')"
  [[ -z "$existing" ]] && continue
  if [[ -n "$(missing_from "$existing")" ]]; then
    echo "verification failed: $conf is still missing tokens" >&2
    rc=1
  fi
done

if (( with_plymouth )); then
  if command -v plymouth >/dev/null 2>&1; then
    echo "plymouth: $(plymouth-set-default-theme 2>/dev/null || echo installed)"
  else
    echo "warning: plymouth is not installed" >&2
  fi
fi

fi

if (( rc == 0 )); then
  if (( changed )); then
    echo "boot splash configured. Reboot to see it (Esc during boot shows the log)."
  else
    echo "nothing to change: kernel parameters and plymouth are already set up."
  fi
fi
exit "$rc"
