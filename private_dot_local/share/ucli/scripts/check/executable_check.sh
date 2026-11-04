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
#   5. Stale verbs: every `ucli <word>` in the docs, the recipes and the scripts
#      must still name a recipe. A removed or renamed recipe left behind in a
#      doc, a comment or an `echo` is the failure mode this repo keeps hitting
#      (the `gnome` menu, `devbox-shell` and `full-profile` verbs were all named
#      in docs long after they stopped existing); the prose allowlist below is
#      the same idea as shellcheck's disable comments, and it must stay short.
#   6. Exit codes and hidden prompts: a script must not end on a bare
#      conditional `(( 0 )) && …`
#      in the middle of a script is exempt from `set -e`, but as the LAST line
#      its false test becomes the script's exit status — which is how
#      `install-flatpaks.sh base` failed `ucli setup-system` silently after the
#      packages were already installed. Nor may an interactive command have its
#      stderr sent to /dev/null: chsh's password prompt lives on stderr, so
#      `chsh -s … 2>/dev/null` was a silent hang at the end of the shell step.
#   7. shellcheck (if installed), severity=warning: the repo is clean at that
#      level, and a warning is exactly the class of thing that turns into a bug
#      later (unused state, word splitting, masked exit codes). Note the version
#      gap: CI installs Ubuntu's shellcheck (0.9.x), a workstation may have 0.11,
#      and the two do not flag the same set — the tree is clean on both, so a
#      FAIL here that your local shellcheck does not reproduce means yours is
#      newer, not that CI is wrong.
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
# One tree holds shell: ~/.local/share/ucli/scripts, both the scripts that run
# directly and the libs they source (aur, detect, firefox, ui, version-script).
# The libs used to be skipped — a syntax error there breaks every caller and
# nothing caught it.
bash_files=()
while IFS= read -r f; do bash_files+=("$f"); done < <(
  find "$scripts_dir" -name '*.sh' -type f 2>/dev/null | sort
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
# 5. stale verbs: `ucli <word>` in docs/recipes/scripts must name a recipe
# ---------------------------------------------------------------------------
justfile="$(find "$config_dir" -maxdepth 1 -name 'justfile' -type f | head -1)"
recipes_dir=""
[[ -n "$justfile" ]] && recipes_dir="$(dirname "$justfile")/recipes"

if [[ -n "$justfile" && -r "$justfile" && -d "$recipes_dir" ]]; then
  recipe_names="$(
    {
      sed -n 's/^\([A-Za-z_][A-Za-z0-9_-]*\)\([[:space:]][^:]*\)\?:[[:space:]]*$/\1/p' "$justfile"
      for f in "$recipes_dir"/*.just; do
        sed -n 's/^\([A-Za-z_][A-Za-z0-9_-]*\)\([[:space:]][^:]*\)\?:[[:space:]]*$/\1/p' "$f"
      done
    } | sort -u
  )"

  # Words that follow "ucli" in ordinary prose. None of these is a recipe —
  # keep it that way, or the check stops being able to see a real rename.
  prose="runtime scripts script wrapper itself step only layer is works tree
  recipes recipe pacman packages on machine home command and"

  mapfile -t scan_files < <(
    find "$scripts_dir" "$config_dir" -type f \
      \( -name '*.sh' -o -name '*.just' -o -name '*.bash' -o -name '*.md' -o -name '*.zsh' \) 2>/dev/null
    [[ -f "$root/README.md" ]] && echo "$root/README.md"
    [[ -d "$root/docs" ]] && find "$root/docs" -name '*.md' -type f
  )

  stale=0
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    tok="${hit##*ucli }"
    grep -qxF -- "$tok" <<<"$recipe_names" && continue
    for word in $prose; do
      [[ "$tok" == "$word" ]] && continue 2
    done
    fail_msg x "ucli $tok is not a recipe (${hit#"$root"/})"
    stale=1
  done < <(
    if ((${#scan_files[@]})); then
      grep -HnoE '(^|[^[:alnum:]_./-])ucli [a-z][a-z0-9_-]*' "${scan_files[@]}" 2>/dev/null || true
    fi
  )
  [[ $stale -eq 0 ]] && note "verbs" "$(wc -w <<<"$recipe_names") recipes, no stale \`ucli\` names"
else
  fail_msg x "cannot check stale verbs (justfile / recipes/ missing)"
fi

# ---------------------------------------------------------------------------
# 6. exit codes: no script may end on a bare conditional
# ---------------------------------------------------------------------------
lastfail=0
for f in "${bash_files[@]:-}"; do
  [[ -n "$f" ]] || continue
  last="$(grep -v '^[[:space:]]*$' "$f" | tail -1)"
  case "$last" in
    *'[['*'&&'* | *'(('*'&&'*)
      fail_msg x "ends with a conditional (false test = exit 1): ${f#"$root"/}"
      lastfail=1
      ;;
  esac
done
[[ $lastfail -eq 0 ]] && note "exit codes" "no script ends with a bare conditional"

# Interactive commands read from the terminal and prompt on stderr: silencing
# stderr turns them into a hang with nothing on screen.
promptfail=0
for f in "${bash_files[@]:-}"; do
  [[ -n "$f" ]] || continue
  # Not this file: its own patterns and comments name the tools on purpose.
  [[ "$(basename "$f")" == "check.sh" || "$(basename "$f")" == "executable_check.sh" ]] && continue
  while IFS= read -r line; do
    # grep -n prefixes "N:", so drop it before looking for a comment
    body="${line#*:}"
    case "$body" in
      \#*) continue ;;
    esac
    if [[ "$body" == *"2>/dev/null"* ]]; then
      fail_msg x "interactive command with hidden stderr (${f#"$root"/}): ${body#"${body%%[![:space:]]*}"}"
      promptfail=1
    fi
  # `getent passwd … 2>/dev/null` and `gpg --verify … 2>/dev/null` are not
  # prompts, and gpg is not in the list for that reason.
  done < <({
    grep -nE '(^|[^[:alnum:]_])(chsh|passwd|ssh-keygen|ssh-add)([^[:alnum:]_]|$)' "$f" 2>/dev/null |
      grep -vE 'getent[[:space:]]+passwd'
  } || true)
done
[[ $promptfail -eq 0 ]] && note "prompts" "no interactive command hides its stderr"

# ---------------------------------------------------------------------------
# 7. shellcheck (optional)
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
