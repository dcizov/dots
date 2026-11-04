#!/usr/bin/env bash
# Offline static checks for the dotfiles repo and for a deployed ucli home.
#
#   check.sh [ROOT]      ROOT defaults to $HOME
#     ROOT=<repo checkout>   checks the sources (private_dot_* layout)
#     ROOT=$HOME             checks what chezmoi deployed
#
# Deliberately cheap, offline and dependency-light so it can run in CI and as
# `ucli check` on any machine. Network checks (pacman -Si, AUR lookups) are NOT
# here — that is `ucli validate`.
#
# What it catches, and why each one exists:
#   1. bash -n over every shipped script — the sweep that would have caught the
#      broken `just` block recipes, which fail silently instead of loudly.
#   2. zsh -n over ~/.zshrc and ~/.config/zsh/{pre-omz.zsh,conf.d/*.zsh}.
#   3. `just --list` — a recipe whose comment sits above a shebang body turns
#      into a line-wise recipe and only shows up when you run it.
#   4. Array consistency: every $ARRAY named by validate-packages.sh and every
#      `add_array X` in install-packages.sh must exist in packages.bash. This is
#      the check that catches a rename (SHELL_DEPS -> SHELL_TOOLS) on one side
#      only.
#   5. shellcheck (if installed), severity=warning: the repo is clean at that
#      level, and a warning is exactly the class of thing that turns into a bug
#      later (unused state, word splitting, masked exit codes).
set -euo pipefail

root=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) root="$arg" ;;
  esac
done
root="${root:-$HOME}"

# ---------------------------------------------------------------------------
# Locate the two possible layouts.
# ---------------------------------------------------------------------------
if [[ -d "$root/private_dot_local/share/ucli" ]]; then
  layout="repo"
  scripts_dir="$root/private_dot_local/share/ucli/scripts"
  config_dir="$root/private_dot_config/ucli"
  zsh_dir="$root/private_dot_config/zsh"
  zshrc="$root/dot_zshrc"
  extra_shell=()
  while IFS= read -r f; do extra_shell+=("$f"); done < <(
    find "$root" -maxdepth 1 -name '*.sh' -type f ! -name '*.tmpl' | sort
  )
elif [[ -d "$root/.local/share/ucli" ]]; then
  layout="deployed"
  scripts_dir="$root/.local/share/ucli/scripts"
  config_dir="$root/.config/ucli"
  zsh_dir="$root/.config/zsh"
  zshrc="$root/.zshrc"
  extra_shell=()
else
  echo "check: no ucli tree under $root" >&2
  exit 1
fi

fail=0
note() { printf '  %-10s %s\n' "$1" "$2"; }
fail_msg() { printf '  %-10s %s\n' "FAIL" "$2"; fail=1; }

echo "check: layout=$layout root=$root"
echo

# ---------------------------------------------------------------------------
# 1. bash -n
# ---------------------------------------------------------------------------
# Two trees hold shell: ~/.local/share/ucli/scripts (run directly) and
# ~/.config/ucli/scripts (the libs they source: detect, ui, choose,
# version-script, firefox). The libs used to be skipped — a syntax error there
# breaks every caller and nothing caught it.
bash_files=()
while IFS= read -r f; do bash_files+=("$f"); done < <(
  find "$scripts_dir" "$config_dir/scripts" -name '*.sh' -type f 2>/dev/null | sort
)
for f in "${extra_shell[@]:-}"; do
  [[ -n "$f" ]] && bash_files+=("$f")
done

n=0
bash_fail=0
for f in "${bash_files[@]:-}"; do
  [[ -n "$f" ]] || continue
  if bash -n "$f" 2>/dev/null; then
    n=$((n + 1))
  else
    bash_fail=1
    out="$(bash -n "$f" 2>&1 | head -3 | tr '\n' ' ')"
    fail_msg x "bash -n ${f#"$root"/}: $out"
  fi
done
[[ $bash_fail -eq 0 ]] && note "bash -n" "$n files"

# ---------------------------------------------------------------------------
# 2. zsh -n
# ---------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  zsh_files=()
  [[ -r "$zshrc" ]] && zsh_files+=("$zshrc")
  [[ -r "$zsh_dir/pre-omz.zsh" ]] && zsh_files+=("$zsh_dir/pre-omz.zsh")
  if [[ -d "$zsh_dir/conf.d" ]]; then
    while IFS= read -r f; do zsh_files+=("$f"); done < <(
      find "$zsh_dir/conf.d" -name '*.zsh' -type f | sort
    )
  fi
  zm=0
  for f in "${zsh_files[@]:-}"; do
    [[ -n "$f" ]] || continue
    if zsh -n "$f" 2>/dev/null; then
      zm=$((zm + 1))
    else
      out="$(zsh -n "$f" 2>&1 | head -3 | tr '\n' ' ')"
      fail_msg x "zsh -n ${f#"$root"/}: $out"
    fi
  done
  note "zsh -n" "$zm files"
else
  note "zsh -n" "skipped (zsh not installed)"
fi

# ---------------------------------------------------------------------------
# 3. just parses
# ---------------------------------------------------------------------------
if command -v just >/dev/null 2>&1; then
  justfile="$config_dir/justfile"
  if [[ -r "$justfile" ]]; then
    if out="$(just --justfile "$justfile" --list 2>&1)"; then
      note "just" "$(grep -c '^    ' <<<"$out") recipes, parses"
    else
      fail_msg x "just --list: $(head -3 <<<"$out" | tr '\n' ' ')"
    fi
  else
    fail_msg x "justfile missing: $justfile"
  fi
else
  note "just" "skipped (just not installed)"
fi

# ---------------------------------------------------------------------------
# 4. package arrays: defined once, referenced consistently
# ---------------------------------------------------------------------------
packages_bash="$config_dir/packages.bash"
validator="$(find "$scripts_dir" -maxdepth 2 -name '*validate-packages.sh' -type f | head -1)"
installer="$(find "$scripts_dir" -maxdepth 2 -name '*install-packages.sh' -type f | head -1)"

if [[ -r "$packages_bash" && -r "$validator" && -r "$installer" ]]; then
  referenced=()
  while IFS= read -r name; do
    referenced+=("$name")
  done < <(
    {
      sed -n '/^package_arrays=(/,/^)/p' "$validator" | sed -e '1d' -e '/^)/d' | tr -s ' ' '\n'
      grep -oE 'add_array [A-Z_]+' "$installer" | awk '{print $2}'
      grep -oE 'add_service_array [A-Z_]+' "$installer" | awk '{print $2}'
    } | grep -E '^[A-Z][A-Z0-9_]*$' | sort -u
  )

  undefined=0
  for name in "${referenced[@]}"; do
    if ! bash -c 'source "$1" >/dev/null 2>&1; declare -p "$2" >/dev/null 2>&1' _ \
        "$packages_bash" "$name"; then
      fail_msg x "\$$name is referenced by the scripts but not defined in packages.bash"
      undefined=1
    fi
  done
  [[ $undefined -eq 0 ]] && note "arrays" "${#referenced[@]} package arrays resolve"
else
  fail_msg x "cannot check package arrays (packages.bash / validate-packages.sh / install-packages.sh)"
fi

# ---------------------------------------------------------------------------
# 5. shellcheck (optional)
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  sc_fail=0
  for f in "${bash_files[@]:-}"; do
    [[ -n "$f" ]] || continue
    if ! out="$(shellcheck --severity=warning --shell=bash --format=gcc "$f" 2>&1)"; then
      sc_fail=1
      echo "$out" | head -5 | sed 's/^/  /' >&2
      fail_msg x "shellcheck ${f#"$root"/}"
    fi
  done
  [[ $sc_fail -eq 0 ]] && note "shellcheck" "severity=warning clean"
else
  note "shellcheck" "skipped (not installed)"
fi

echo
if [[ $fail -ne 0 ]]; then
  echo "check: FAILED" >&2
  exit 1
fi
echo "check: ok"
