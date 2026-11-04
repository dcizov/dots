# Shared gum UI helpers for ucli recipes and scripts. Sourced, never executed.
#
# Ported from Bluefin's `ujust toggle-devmode` wizard (projectbluefin/common,
# system.just): title/summary boxes, a sectioned `gum choose --no-limit` screen
# with preselection, and a block-character progress bar with per-step ✓/✗.
#
# Everything degrades to plain line output when gum is missing or when stdout
# is not a terminal (CI, `ucli devmode --all`, piped runs).
#
# Usage:
#   . "$HOME/.config/ucli/scripts/lib/ui.sh"
#   ui_title "Turn on Developer Mode"
#   picks="$(ui_choose_multi 'What should I install?' \
#              --selected '  Dev CLI,  Dev packages' \
#              '── Toolchain ────────' \
#              '  Dev CLI' '  Dev packages')" || exit 0
#   ui_summary "Ready to install:" $picks
#   ui_step 1 2 "Dev CLI" -- install-packages.sh dev-cli

# shellcheck shell=bash

[ -n "${_UCLI_UI_LOADED:-}" ] && return 0
_UCLI_UI_LOADED=1

ui_have() { command -v "$1" >/dev/null 2>&1; }

# Interactive means "someone can type at us", i.e. stdin is a terminal. Do not
# test stdout: callers capture menu output in $(...), so stdout is a pipe even
# in an interactive session. gum renders its TUI on stderr and prints the final
# selection to stdout, which is exactly what captured output needs.
ui_tty() { [ -t 0 ]; }
ui_gum() { ui_have gum && ui_tty; }

# ui_title <text> — double-bordered headline (like the devmode banner).
ui_title() {
  if ui_gum; then
    gum style --foreground 212 --border-foreground 212 --border double \
      --align center --width 60 --padding "1 4" "$*"
  else
    printf '\n==> %s\n\n' "$*"
  fi
}

# ui_box <text> — rounded callout, for closing words.
ui_box() {
  if ui_gum; then
    gum style --border rounded --border-foreground 212 --padding "1 3" \
      --width 60 "$*"
  else
    printf '\n%s\n' "$*"
  fi
}

# ui_summary <heading> <item>... — "Ready to install" checklist.
ui_summary() {
  local heading="$1"; shift
  local body line
  body="$heading"
  for line in "$@"; do
    body+=$'\n'"  ● ${line}"
  done
  if ui_gum; then
    gum style --bold --border rounded --border-foreground 212 \
      --padding "1 3" --width 60 "$body"
  else
    printf '%s\n' "$body"
  fi
}

ui_ok()   { if ui_gum; then gum style --foreground 42 "✓ $*"; else printf '✓ %s\n' "$*"; fi; }
ui_fail() { if ui_gum; then gum style --foreground 196 "✗ $*" >&2; else printf '✗ %s\n' "$*" >&2; fi; }

# _ui_bar <done> <total> — 24-cell block bar.
_ui_bar() {
  local done=$1 total=$2 width=24 filled bar
  (( total > 0 )) || { printf '%*s' "$width" ''; return; }
  filled=$(( done * width / total ))
  printf -v bar '%*s' "$filled" ''
  bar="${bar// /█}"
  printf -v bar '%s%*s' "$bar" $(( width - filled )) ''
  bar="${bar// /░}"
  printf '%s' "$bar"
}

# ui_step <index> <total> <label> -- <command...>
# index is 0-based, like Bluefin's _dx_step. Prints "✓ label" on success and
# "✗ label" plus a non-zero status on failure (callers decide to abort).
ui_step() {
  local idx=$1 total=$2 label=$3
  shift 3
  [[ "${1:-}" == "--" ]] && shift

  local bar counter digits
  bar="$(_ui_bar "$idx" "$total")"
  digits=${#total}
  printf -v counter "%*d/%*d" "$digits" "$(( idx + 1 ))" "$digits" "$total"

  if ui_gum; then
    if gum spin --spinner dot --title " ${bar}  ${counter}  ${label}" -- "$@"; then
      ui_ok "$label"
    else
      ui_fail "$label"
      return 1
    fi
  else
    printf '==> [%s %s] %s\n' "$bar" "$counter" "$label"
    if "$@"; then
      ui_ok "$label"
    else
      ui_fail "$label"
      return 1
    fi
  fi
}

# ui_choose_multi <header> [--selected <csv>] [--height <n>] <item>...
#
# Items are printed verbatim; a line starting with "──" is treated as a section
# heading (Bluefin's trick) and is never returned. Selected items are returned
# one per line with their leading indentation stripped.
#
# --selected takes a comma-separated list of item labels exactly as written,
# including their leading indentation (e.g. --selected '  Dev CLI,  Dev box').
ui_choose_multi() {
  local header="${1:-}"
  shift || true
  local selected="" height=22

  while (($#)); do
    case "$1" in
      --selected) selected="${2:-}"; shift 2 ;;
      --height)   height="${2:-22}"; shift 2 ;;
      --)         shift; break ;;
      *)          break ;;
    esac
  done

  (($#)) || return 1
  local -a items=("$@")

  local out=""
  if ui_gum; then
    local -a args=(--no-limit --height "$height" --cursor "▸  "
                   --selected-prefix "◉  " --unselected-prefix "○  ")
    [[ -n "$selected" ]] && args+=(--selected "$selected")
    out="$(printf '%s\n' "${items[@]}" | gum choose "${args[@]}")" || return 1
  elif ui_tty; then
    # Plain numbered fallback: "1 3" or "1,3" or "all". Section headings are
    # printed but not numbered, so the numbers match what is on screen.
    local i n=0
    local -a pickable=()
    printf '\n%s\n' "$header" >&2
    for i in "${!items[@]}"; do
      if [[ "${items[$i]}" == ──* ]]; then
        printf '%s\n' "${items[$i]}" >&2
        continue
      fi
      pickable+=("$i")
      n=$(( n + 1 ))
      printf '  %2d) %s\n' "$n" "${items[$i]#  }" >&2
    done
    printf 'Select numbers (space or comma separated, "all" for everything): ' >&2
    local answer
    read -r answer || return 1
    if [[ "${answer,,}" == all ]]; then
      for i in "${pickable[@]}"; do out+="${items[$i]}"$'\n'; done
    else
      answer="${answer//,/ }"
      local k
      for k in $answer; do
        [[ "$k" =~ ^[0-9]+$ ]] || continue
        (( k >= 1 && k <= ${#pickable[@]} )) || continue
        out+="${items[${pickable[$(( k - 1 ))]}]}"$'\n'
      done
    fi
    out="${out%$'\n'}"
    [[ -n "$out" ]] || return 1
  else
    # Non-interactive: caller asked for a menu but nothing can answer it.
    return 1
  fi

  printf '%s\n' "$out" | while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line}" == ──* ]] && continue
    printf '%s\n' "${line#  }"
  done
}

# Single-select menus (`ui_choose`), confirmations (`ui_confirm`) and `show`
# live in choose.sh; pull them in so callers only source this one file.
if [ -z "${_UCLI_CHOOSE_SOURCED:-}" ] && [ -r "$(dirname -- "${BASH_SOURCE[0]}")/choose.sh" ]; then
  _UCLI_CHOOSE_SOURCED=1
  # shellcheck source=/dev/null
  . "$(dirname -- "${BASH_SOURCE[0]}")/choose.sh"
fi
