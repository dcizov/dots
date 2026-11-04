#!/usr/bin/env bash
# Health check for a ucli machine. Prints one line per thing that can be wrong,
# in the order you would debug it: dotfiles → shell → tools → dev box → desktop.
#
#   ucli doctor
#
# Read-only: it never installs, applies or changes anything. Exit status is 1 if
# something is MISSING, 0 otherwise (WARN lines do not fail the run).
set -euo pipefail

real_home="${HOME:-$(getent passwd "${USER:-$(id -un)}" | cut -d: -f6)}"
config_dir="$real_home/.config/ucli"
zsh_dir="$real_home/.config/zsh"
missing=0
warned=0

ok() { printf '  %-10s %s\n' "OK" "$1"; }
miss() { printf '  %-10s %s\n' "MISSING" "$1"; missing=$((missing + 1)); }
warn() { printf '  %-10s %s\n' "WARN" "$1"; warned=$((warned + 1)); }
info() { printf '  %-10s %s\n' "—" "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

# A desktop exists once one of its session binaries does. Before that the box is a
# console install: .chezmoiignore keeps the shell/terminal/browser config out of
# $HOME by design, so their absence is the expected state, not a fault.
desktop_epoch=0
for _de_bin in gnome-shell plasmashell Hyprland hyprland startplasma-wayland; do
  have "$_de_bin" && desktop_epoch=1 && break
done

# Same line, different weight: MISSING before a desktop exists is noise, because
# .chezmoiignore is deliberately holding those files back until the program lands.
miss_or_note() {
  if (( desktop_epoch )); then
    miss "$1"
  else
    info "$1 — expected on a console-only box"
  fi
}

# ---------------------------------------------------------------------------
section "dotfiles"
if have chezmoi; then
  mkdir -p "$real_home/.cache/tmp"
  if TMPDIR="$real_home/.cache/tmp" chezmoi doctor >/dev/null 2>&1; then
    ok "chezmoi doctor"
  else
    warn "chezmoi doctor reports problems (run: chezmoi doctor)"
  fi
  if [[ -n "$(chezmoi diff 2>/dev/null | head -1)" ]]; then
    warn "chezmoi diff is not empty (run: chezmoi diff, then chezmoi apply -v)"
  else
    ok "chezmoi diff empty (deployed)"
  fi
else
  miss "chezmoi (run install.sh)"
fi
if [[ -e "$config_dir/justfile" ]]; then
  ok ".config/ucli/justfile"
else
  miss ".config/ucli/justfile (run: install.sh, or: ucli chezmoi-apply)"
fi
# The shell layer is deployed by .chezmoiignore only once zsh exists, so on a
# console-only machine these two are supposed to be missing.
for path in "$real_home/.zshrc" "$zsh_dir/plugins.txt"; do
  if [[ -e "$path" ]]; then
    ok "${path#"$real_home"/}"
  else
    miss_or_note "${path#"$real_home"/} (run: ucli chezmoi-apply)"
  fi
done
if [[ -e "$real_home/.bash_profile" ]] && grep -q '.local/bin' "$real_home/.bash_profile" 2>/dev/null; then
  ok ".bash_profile puts ~/.local/bin on PATH"
else
  miss "~/.bash_profile with ~/.local/bin on PATH (run: ucli chezmoi-apply)"
fi

# ---------------------------------------------------------------------------
section "shell"
if have zsh; then
  zsh_bad=0
  for f in "$real_home/.zshrc" "$zsh_dir/pre-omz.zsh" "$zsh_dir"/conf.d/*.zsh; do
    [[ -r "$f" ]] || continue
    if ! zsh -n "$f" 2>/dev/null; then
      warn "zsh -n failed: ${f#"$real_home"/}"
      zsh_bad=1
    fi
  done
  [[ $zsh_bad -eq 0 ]] && ok "zsh parses ~/.zshrc, pre-omz.zsh and conf.d"
else
  miss_or_note "zsh (run: ucli cli)"
fi

login_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
if [[ "$login_shell" == *zsh ]]; then
  ok "login shell is zsh ($login_shell)"
elif have zsh; then
  warn "login shell is $login_shell (chsh -s \"$(command -v zsh)\", or re-run: ucli cli)"
else
  miss_or_note "login shell is $login_shell (run: ucli cli)"
fi

if [[ -r "$real_home/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  ok "oh-my-zsh"
else
  miss_or_note "~/.oh-my-zsh (run: ucli cli)"
fi

if have starship; then
  if [[ -r "$real_home/.config/starship.toml" ]]; then
    ok "starship + ~/.config/starship.toml"
  else
    warn "starship installed but ~/.config/starship.toml missing (default prompt)"
  fi
else
  miss_or_note "starship (run: ucli cli)"
fi

# expected plugins come from the one shared list; compare with what is on disk
if [[ -r "$zsh_dir/plugins.txt" ]]; then
  plugin_root="${ZSH_CUSTOM:-$real_home/.oh-my-zsh/custom}/plugins"
  plugin_missing=()
  while IFS= read -r repo; do
    name="${repo#*/}"
    [[ -d "$plugin_root/$name/.git" ]] || plugin_missing+=("$name")
  done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$zsh_dir/plugins.txt" | grep -v '^$')
  if ((${#plugin_missing[@]} == 0)); then
    ok "zsh plugins (from plugins.txt)"
  else
    miss "zsh plugins: ${plugin_missing[*]} (run: ucli cli)"
  fi
fi

motd_mode="$(cat "${XDG_STATE_HOME:-$real_home/.local/state}/ucli/motd" 2>/dev/null || echo "on (default)")"
if have fastfetch; then
  if [[ "$motd_mode" == "off" ]]; then
    ok "motd off (fastfetch installed)"
  else
    ok "motd: $motd_mode (fastfetch installed)"
  fi
else
  warn "fastfetch missing — the login banner is skipped (ucli motd off silences the check)"
fi

if [[ -r "$zsh_dir/local.zsh" ]]; then
  ok "~/.config/zsh/local.zsh (machine overrides)"
else
  info "no local.zsh — per-machine overrides go there (cp local.zsh.example)"
fi

# flags are defaults in conf.d; show which ones exist so a "why is ls GNU again"
# question has a starting point
if [[ -d "$zsh_dir/conf.d" ]]; then
  flags="$(grep -ho 'UCLI_SHELL_ENABLE_[A-Z]*' "$zsh_dir"/conf.d/*.zsh 2>/dev/null |
    sort -u | sed 's/^UCLI_SHELL_ENABLE_//' | tr '\n' ' ')"
  [[ -n "$flags" ]] && info "shell flags available: ${flags% }"
fi

# ---------------------------------------------------------------------------
section "ucli runtime"
for cmd in just gum pipx; do
  if have "$cmd"; then ok "$cmd"; else miss "$cmd (run: ucli cli / ucli setup-system)"; fi
done
if have gext; then
  ok "gext (gnome-extensions-cli)"
else
  warn "gext missing — GNOME extension sets cannot install (ucli install-gnome-extensions-cli)"
fi
if have paru; then
  ok "AUR helper: paru"
elif have shelly; then
  ok "AUR helper: shelly"
else
  warn "no AUR helper (paru/shelly) — AUR packages will be skipped"
fi
if have flatpak; then
  ok "flatpak"
else
  warn "flatpak missing — flatpaks in ucli apps are skipped"
fi

# ---------------------------------------------------------------------------
section "apps"
if have firefox; then
  # Firefox 147+ keeps profiles in ~/.config/mozilla/firefox; older installs stay in
  # ~/.mozilla/firefox. lib/firefox.sh knows which one this machine uses.
  if [[ -r "$config_dir/scripts/lib/firefox.sh" ]]; then
    # shellcheck source=/dev/null
    source "$config_dir/scripts/lib/firefox.sh"
    profiles="$(fx_profile_root "$real_home")"
    if [[ -f "$profiles/profiles.ini" ]]; then
      ok "firefox profile root: $(fx_short_root "$profiles" "$real_home")"
      count=0
      while IFS= read -r profile_dir; do
        [[ -n "$profile_dir" ]] && count=$((count + 1))
      done < <(fx_profile_dirs "$profiles")
      info "$count profile(s); user.js copied into each"
      if [[ -f "$(fx_config_dir "$real_home")/user.js" ]]; then
        ok "Betterfox user.js available (~/.config/ucli/firefox/user.js)"
      else
        warn "~/.config/ucli/firefox/user.js missing (run: ucli chezmoi-apply)"
      fi
    else
      info "firefox profile root: $(fx_short_root "$profiles" "$real_home") (no profile yet)"
      warn "firefox has no profile yet (ucli apps creates one headlessly)"
    fi
  else
    warn "$config_dir/scripts/lib/firefox.sh missing (run: ucli chezmoi-apply)"
  fi
else
  warn "firefox missing (run: ucli setup-system / ucli apps)"
fi

if [[ -f /etc/snapper/configs/root ]]; then
  ok "snapper root config (snapshots work)"
else
  warn "no snapper config — setup-desktop cannot take a restore point (ucli setup-snapshots)"
fi

desktop="${XDG_CURRENT_DESKTOP:-none}"
case "${desktop,,}" in
  *gnome*)
    if have gsettings; then
      enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo none)"
      count="$(grep -o "'" <<<"$enabled" | wc -l)"
      ok "gnome: ${count} extensions enabled"
    fi
    ;;
  *) info "desktop: ${desktop:-unknown}" ;;
esac

# ---------------------------------------------------------------------------
section "versioned gates"
state_dir="${XDG_STATE_HOME:-$real_home/.local/state}/ucli"
if [[ -d "$state_dir/gates" ]]; then
  while IFS=$'\t' read -r scope name version; do
    info "gate $scope/$name = $version"
  done < <(
    find "$state_dir/gates" -type f | sort | while IFS= read -r f; do
      printf '%s\t%s\t%s\n' "$(basename "$(dirname "$f")")" "$(basename "$f")" "$(head -n1 "$f")"
    done
  )
else
  info "no gates committed yet"
fi
if [[ -f "$state_dir/devmode" ]]; then
  info "devmode marker: $(grep -c '^[a-z-]*=' "$state_dir/devmode" 2>/dev/null) fields"
fi

# ---------------------------------------------------------------------------
section "dev box"
if have distrobox; then
  ok "distrobox"
  if distrobox list --no-color 2>/dev/null | grep -qE '\bdev\b'; then
    # a container that exists but was never provisioned looks identical to a
    # healthy one unless we ask about the versions the tooling assumes
    out="$(distrobox enter dev -- bash -lc \
      'printf "%s|%s|%s\n" "$(cat /etc/debian_version)" \
      "$(node -v 2>/dev/null || echo MISSING)" \
      "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)"' 2>/dev/null || true)"
    debian="${out%%|*}"; rest="${out#*|}"; node="${rest%%|*}"; php="${rest##*|}"
    if [[ -n "$debian" && "$node" != MISSING && "$php" != MISSING ]]; then
      ok "dev: debian $debian / node $node / php $php"
    else
      warn "dev exists but is not provisioned (node ${node:-?}, php ${php:-?}) — run: ucli devbox-reconcile"
    fi
  else
    info "container dev not created (ucli devbox-reconcile)"
  fi
else
  info "distrobox not installed (dev box unavailable)"
fi

# ---------------------------------------------------------------------------
echo
if ((missing)); then
  printf 'doctor: %d missing, %d warning(s)\n' "$missing" "$warned"
  exit 1
fi
printf 'doctor: ok (%d warning(s))\n' "$warned"
