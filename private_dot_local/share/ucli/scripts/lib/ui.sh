# Shared gum UI layer for ucli recipes and scripts. Sourced, never executed.
#
# Lives next to the scripts that use it (~/.local/share/ucli/scripts/lib), not in
# ~/.config, so a script running under sudo can find it from its own path:
#     . "$(dirname "$0")/../lib/ui.sh"
#
# One visual grammar for every interactive path in ucli, taken from the ujust
# recipes this repo ports (Bluefin's `toggle-devmode` wizard): a title banner,
# menus built with `gum choose`, a summary box before anything runs, a
# block-character progress bar with per-step ✓/✗, and `gum confirm` for yes/no.
#
#   ui_title         double-bordered headline
#   ui_rule          in-flow step heading ("==> text")
#   ui_note          dim continuation line
#   ui_summary       rounded checklist box ("Ready to install:")
#   ui_step          progress bar + ✓/✗ around one command
#   ui_ok / ui_fail  one-line results
#   ui_choose        single-select menu over `tag|description` rows
#   ui_choose_multi  multi-select menu over `section|label` rows
#   ui_confirm       gum confirm, y/N fallback
#   show             pager helper
#
# House style — every script in the repo follows it, so a menu looks the same
# whether it came from `ucli devmode`, `ucli mirrors` or `ucli setup-desktop`:
#
#   * accent colour 212 on every border and cursor, dim 245 for secondary text,
#     42/196 for ✓/✗; boxes are 60 columns wide.
#   * glyphs: ❯ cursor · ◉ selected · ○ unselected · ✓ ok · ✗ fail · ● bullet.
#   * menus print the TUI on stderr and the selection on stdout, so
#     `picks="$(ui_choose_multi …)"` works. Do not test stdout for a TTY.
#   * every menu degrades to a numbered prompt when gum is missing and returns
#     non-zero when nothing can answer it, so callers can fall back to --all.
#   * menu labels never contain a comma: gum's `--selected` is a comma-separated
#     string slice, so one comma inside a label breaks preselection silently.
#   * section headings are NOT fake menu rows (gum cannot render a row that
#     cannot be toggled, and a row you can tick but that does nothing is a bug).
#     Sections are a left-hand column: `toolchain|Dev CLI (jq · ripgrep …)`.
#
# Usage:
#   . "$HOME/.local/share/ucli/scripts/lib/ui.sh"
#   ui_title "Turn on Developer Mode"
#   picks="$(ui_choose_multi 'What should I set up?' \
#              --selected 'Dev CLI (jq · ripgrep · fd · neovim · tmux · mise · …)' \
#              'toolchain|Dev CLI (jq · ripgrep · fd · neovim · tmux · mise · …)' \
#              'containers|Dev box (Debian distrobox + node + php)')" || exit 0
#   ui_summary "Ready to install:" $picks
#   ui_step 0 2 "Dev CLI" -- install-packages.sh dev-cli

# shellcheck shell=bash

[ -n "${_UCLI_UI_LOADED:-}" ] && return 0
_UCLI_UI_LOADED=1

# --- design tokens ----------------------------------------------------------

UCLI_UI_ACCENT=${UCLI_UI_ACCENT:-212}
UCLI_UI_DIM=${UCLI_UI_DIM:-245}
UCLI_UI_OK=${UCLI_UI_OK:-42}
UCLI_UI_FAIL=${UCLI_UI_FAIL:-196}
UCLI_UI_WIDTH=${UCLI_UI_WIDTH:-60}
UCLI_UI_CURSOR=${UCLI_UI_CURSOR:-'❯ '}
UCLI_UI_SELECTED=${UCLI_UI_SELECTED:-'◉  '}
UCLI_UI_UNSELECTED=${UCLI_UI_UNSELECTED:-'○  '}
export UCLI_UI_ACCENT UCLI_UI_DIM UCLI_UI_OK UCLI_UI_FAIL UCLI_UI_WIDTH
export UCLI_UI_CURSOR UCLI_UI_SELECTED UCLI_UI_UNSELECTED

ui_have() { command -v "$1" >/dev/null 2>&1; }

# Interactive means "someone can type at us", i.e. stdin is a terminal. Do not
# test stdout: callers capture menu output in $(...), so stdout is a pipe even
# in an interactive session. gum renders its TUI on stderr and prints the final
# selection to stdout, which is exactly what captured output needs.
ui_tty() { [ -t 0 ]; }
ui_gum() { ui_have gum && ui_tty; }

# --- blocks -----------------------------------------------------------------

# ui_title <text> — double-bordered headline (the devmode banner).
ui_title() {
  if ui_gum; then
    gum style --foreground "$UCLI_UI_ACCENT" --border-foreground "$UCLI_UI_ACCENT" \
      --border double --align center --width "$UCLI_UI_WIDTH" --padding "1 4" "$*"
  else
    printf '\n==> %s\n\n' "$*"
  fi
}

# ui_box <text> — rounded callout, for closing words.
ui_box() {
  if ui_gum; then
    gum style --border rounded --border-foreground "$UCLI_UI_ACCENT" --padding "1 3" \
      --width "$UCLI_UI_WIDTH" "$*"
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
    gum style --bold --border rounded --border-foreground "$UCLI_UI_ACCENT" \
      --padding "1 3" --width "$UCLI_UI_WIDTH" "$body"
  else
    printf '%s\n' "$body"
  fi
}

# ui_rule <text> — in-flow step heading, the one used inside a long run.
ui_rule() {
  if ui_have gum && [ -t 1 ]; then
    printf '\n'
    gum style --foreground "$UCLI_UI_ACCENT" --bold "==> $*"
  else
    printf '\n==> %s\n' "$*"
  fi
}

# ui_note <text> — dim continuation line under a rule.
ui_note() {
  if ui_have gum && [ -t 1 ]; then
    gum style --foreground "$UCLI_UI_DIM" "    $*"
  else
    printf '    %s\n' "$*"
  fi
}

# ui_hint <text> — dim one-liner, mostly "space = toggle · enter = confirm".
ui_hint() {
  if ui_have gum && [ -t 1 ]; then
    gum style --foreground "$UCLI_UI_DIM" "  $*" >&2
  else
    printf '  %s\n' "$*" >&2
  fi
}

# ui_link <url> [text] — a clickable link where the terminal supports OSC 8,
# the bare URL everywhere else (pipes, CI, UCLI_NO_LINKS=1). Same idea as ujust's
# Urllink helper; kept here so every script prints links the same way.
ui_link() {
  local url="$1" text="${2:-$1}"
  if [[ "${UCLI_NO_LINKS:-0}" == 1 ]] || ! ui_tty; then
    printf '%s' "$text"
    [[ "$text" == "$url" ]] || printf ' (%s)' "$url"
    return 0
  fi
  printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$text"
}

ui_ok()   { if ui_gum; then gum style --foreground "$UCLI_UI_OK" "✓ $*"; else printf '✓ %s\n' "$*"; fi; }
ui_fail() { if ui_gum; then gum style --foreground "$UCLI_UI_FAIL" "✗ $*" >&2; else printf '✗ %s\n' "$*" >&2; fi; }

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

# --- menus ------------------------------------------------------------------

# _ui_pad <width> <text> — left-aligned padding without a subprocess.
_ui_pad() { local w=$1 t=$2; printf -v t "%-${w}s" "$t"; printf '%s' "$t"; }

# ui_choose <header> <tag|description>...
#
# Single select. The tag is what comes back on stdout, the description is what
# makes a 40-recipe menu readable. Rows are handed to gum pre-padded so the two
# columns line up without an embedded delimiter.
ui_choose() {
  local header="${1:-}"; shift
  (($#)) || return 1

  local -a tags=() lines=()
  local item max=0 pad
  for item in "$@"; do tags+=("${item%%|*}"); done
  for item in "${tags[@]}"; do (( ${#item} > max )) && max=${#item}; done
  pad=$(( max + 2 ))
  for item in "$@"; do
    if [[ "$item" == *"|"* ]]; then
      lines+=("$(_ui_pad "$pad" "${item%%|*}")${item#*|}")
    else
      # A bare label is legal: no description column, nothing to duplicate.
      lines+=("$item")
    fi
  done

  ui_hint "enter = select · ctrl-c = cancel"
  if ui_gum; then
    local pick
    pick="$(printf '%s\n' "${lines[@]}" | gum choose --header "$header" \
      --cursor "$UCLI_UI_CURSOR" --height 14)" || return 1
    [[ -n "${pick//[[:space:]]/}" ]] || return 1
    # gum echoes the whole row (padded tag column + description), so the row has
    # to be mapped back to its tag. Cutting at the first space looked fine and
    # broke the moment a tag contained one: every "Dev box" pick came back as
    # "Dev", which is how the chooser ended in "nothing in that group".
    local i
    for i in "${!lines[@]}"; do
      if [[ "${lines[$i]}" == "$pick" ]]; then
        printf '%s\n' "${tags[$i]}"
        return 0
      fi
    done
    # gum trims trailing whitespace on some terminals: fall back to the longest
    # tag the picked row starts with.
    local tag best="" bestlen=0
    for tag in "${tags[@]}"; do
      if [[ "$pick" == "$tag" || "$pick" == "$tag "* ]] && (( ${#tag} > bestlen )); then
        best="$tag"
        bestlen=${#tag}
      fi
    done
    [[ -n "$best" ]] || return 1
    printf '%s\n' "$best"
    return 0
  fi
  ui_tty || return 1

  printf '\n%s\n' "$header" >&2
  local i n=0
  for i in "${!lines[@]}"; do
    n=$(( n + 1 ))
    printf '  %2d) %s\n' "$n" "${lines[$i]}" >&2
  done
  printf 'Select a number: ' >&2
  local answer
  read -r answer || return 1
  [[ "$answer" =~ ^[0-9]+$ ]] || return 1
  (( answer >= 1 && answer <= ${#lines[@]} )) || return 1
  printf '%s\n' "${tags[$(( answer - 1 ))]}"
}

# ui_choose_multi <header> [--selected <csv of labels>] [--height <n>] <item>...
#
# Multi select. An item is either "label" or "section|label"; the section is
# rendered as a left-hand column, never as a row of its own, because gum has no
# way to render a row that cannot be toggled and a heading you can tick but that
# does nothing is a bug (that is what this replaced).
#
# Returns the labels, one per line, with no section column, so callers map back
# to their own ids. --selected takes labels exactly as written (no section).
ui_choose_multi() {
  local header="${1:-}"
  shift || true
  local selected_csv="" height=22

  while (($#)); do
    case "$1" in
      --selected) selected_csv="${2:-}"; shift 2 ;;
      --height)   height="${2:-22}"; shift 2 ;;
      --)         shift; break ;;
      *)          break ;;
    esac
  done

  (($#)) || return 1

  local -a labels=() sections=() rows=()
  local item sec lbl maxsec=0 i
  for item in "$@"; do
    if [[ "$item" == *"|"* ]]; then
      sec="${item%%|*}"
      lbl="${item#*|}"
    else
      sec=""
      lbl="$item"
    fi
    sections+=("$sec")
    labels+=("$lbl")
    (( ${#sec} > maxsec )) && maxsec=${#sec}
  done

  for i in "${!labels[@]}"; do
    if (( maxsec > 0 )); then
      rows+=("$(_ui_pad "$maxsec" "${sections[$i]}")  ${labels[$i]}")
    else
      rows+=("${labels[$i]}")
    fi
  done

  local out=""
  if ui_gum; then
    local -a args=(--no-limit --height "$height" --cursor "$UCLI_UI_CURSOR"
                   --selected-prefix "$UCLI_UI_SELECTED" --unselected-prefix "$UCLI_UI_UNSELECTED")
    # Preselect by row text. gum splits --selected on commas, which is why menu
    # labels must not contain one (see the header); one flag per label is fine.
    if [[ -n "$selected_csv" ]]; then
      local -a wanted=()
      local csv="$selected_csv,"
      while [[ -n "$csv" ]]; do wanted+=("${csv%%,*}"); csv="${csv#*,}"; done
      local want found
      for want in "${wanted[@]}"; do
        [[ -n "${want//[[:space:]]/}" ]] || continue
        found=""
        for i in "${!labels[@]}"; do
          if [[ "${labels[$i]}" == "$want" ]]; then found="${rows[$i]}"; break; fi
        done
        [[ -n "$found" ]] && args+=(--selected "$found")
      done
    fi

    ui_hint "space = toggle · enter = confirm · ctrl-c = cancel"
    out="$(printf '%s\n' "${rows[@]}" | gum choose "${args[@]}")" || return 1
  elif ui_tty; then
    ui_hint "numbers (space or comma separated), \"all\", or empty to cancel"
    printf '\n%s\n' "$header" >&2
    local n=0
    for i in "${!rows[@]}"; do
      n=$(( n + 1 ))
      printf '  %2d) %s\n' "$n" "${rows[$i]}" >&2
    done
    printf 'Select: ' >&2
    local answer
    read -r answer || return 1
    # Rows, not labels: the mapping below turns rows back into labels, so both
    # backends return the same thing.
    if [[ "${answer,,}" == all ]]; then
      for i in "${!rows[@]}"; do out+="${rows[$i]}"$'\n'; done
    else
      answer="${answer//,/ }"
      local k
      for k in $answer; do
        [[ "$k" =~ ^[0-9]+$ ]] || continue
        (( k >= 1 && k <= ${#rows[@]} )) || continue
        out+="${rows[$(( k - 1 ))]}"$'\n'
      done
    fi
    out="${out%$'\n'}"
  else
    # Caller asked for a menu but nothing can answer it.
    return 1
  fi

  # rows -> labels (gum echoes the padded row, including the section column)
  local line hit
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    hit=""
    for i in "${!rows[@]}"; do
      if [[ "${rows[$i]}" == "$line" ]]; then hit="${labels[$i]}"; break; fi
    done
    [[ -n "$hit" ]] && printf '%s\n' "$hit"
  done <<<"$out"

  [[ -n "$out" ]]
}

# ui_confirm <question>  → 0 = yes, 1 = no
ui_confirm() {
  local prompt="$1" ans
  if ui_gum; then
    gum confirm --affirmative "Yes" --negative "No" "$prompt"
    return
  fi
  ui_tty || return 1
  read -r -p "$prompt [y/N] " ans || return 1
  [[ "${ans:-}" == [yY]* ]]
}

# show <cmd...> — page the output when it is a terminal, otherwise just print it.
# A pager that quits after one screen (less -F) makes the producer die of
# SIGPIPE, which under `set -o pipefail` surfaces as exit 141 and fails the
# recipe. 141 from the producer is normal here, not an error.
show() {
  local rc=0
  if [ -t 1 ] && command -v "${PAGER:-less}" >/dev/null 2>&1; then
    set +o pipefail
    "$@" | ${PAGER:-less -FRX}
    rc=${PIPESTATUS[0]}
    set -o pipefail
    [ "$rc" -eq 141 ] && rc=0
  else
    "$@" || rc=$?
  fi
  return "$rc"
}
