# Shared interactive helpers for ucli recipes. Sourced, never executed.
#
# One menu API, three backends, in order of preference:
#
#   fzf     fuzzy filter with the descriptions visible (already in CLI=)
#   gum     charmbracelet's TUI — what ujust uses (`gum choose`, `gum confirm`);
#           nicer headers/confirm, but an extra binary: pacman -S gum
#   select  plain numbered menu, works over any ssh/dumb terminal
#
# Usage:
#   . "$HOME/.config/ucli/scripts/lib/choose.sh"
#   action="$(ui_choose 'dev box' 'reconcile|create or update' 'shell|open a shell')" || exit 0
#   ui_confirm 'Recreate the container?' && do_it

ui_have() { command -v "$1" >/dev/null 2>&1; }

# ui_choose <header> <tag|description>...   → prints the tag
ui_choose() {
  local header="$1"; shift
  [ "$#" -gt 0 ] || return 1

  if ui_have fzf && [ -t 0 ]; then
    printf '%s\n' "$@" |
      fzf --prompt="$header> " --with-nth=1,2 --delimiter='|' \
          --height=50% --reverse --no-multi |
      awk -F'|' '{print $1}'
    return
  fi

  if ui_have gum && [ -t 0 ]; then
    # gum has no column syntax: render "tag  description" and split on the gap
    local -a display=()
    local item
    for item in "$@"; do display+=("$(printf '%s' "$item" | awk -F'|' '{printf "%-16s %s", $1, $2}')"); done
    gum choose --header="$header" "${display[@]}" |
      awk '{print $1}'
    return
  fi

  printf '\n%s\n\n' "$header" >&2
  local line
  select line in "$@"; do
    [ -n "$line" ] || return 1
    printf '%s\n' "${line%%|*}"
    return 0
  done
  return 1
}

# ui_confirm <question>  → 0 = yes, 1 = no
ui_confirm() {
  local prompt="$1" ans
  if ui_have gum && [ -t 0 ]; then
    gum confirm "$prompt"
    return
  fi
  if ! [ -t 0 ]; then return 1; fi
  read -r -p "$prompt [y/N] " ans
  [[ "${ans:-}" == [yY]* ]]
}
