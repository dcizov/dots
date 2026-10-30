# Shared interactive helpers for ucli recipes. Sourced, never executed.
#
# One menu API, three backends. Default order is gum → fzf → select, because
# gum is what ujust uses (`gum choose` / `gum confirm`) and it looks like the
# rest of the shell. Override with UCLI_MENU=gum|fzf|select.
#
# Usage:
#   . "$HOME/.config/ucli/scripts/lib/choose.sh"
#   action="$(ui_choose 'dev box' 'reconcile|create or update' 'shell|open a shell')" || exit 0
#   ui_confirm 'Recreate the container?' && do_it
#
# Items are authored as `tag|description`; both menu backends are handed
# pre-formatted two-column lines (no visible delimiter) and only the tag is
# returned.

ui_have() { command -v "$1" >/dev/null 2>&1; }

ui_backend() {
  case "${UCLI_MENU:-auto}" in
    gum|fzf|select) printf '%s' "$UCLI_MENU"; return ;;
  esac
  # don't try to run a TUI when nothing is attached; select degrades cleanly
  [ -t 0 ] || { printf 'select'; return; }
  if ui_have gum;   then printf 'gum';   return; fi
  if ui_have fzf;   then printf 'fzf';   return; fi
  printf 'select'
}

# `tag|description` -> `tag        description` (tag column padded)
ui_format() {
  printf '%s\n' "$@" | awk -F'|' '{ printf "%-14s %s\n", $1, $2 }'
}

# ui_choose <header> <tag|description>...   → prints the tag
ui_choose() {
  local header="$1"; shift
  [ "$#" -gt 0 ] || return 1

  local backend; backend="$(ui_backend)"
  local padded; padded="$(ui_format "$@")"

  case "$backend" in
    gum)
      printf '%s\n' "$padded" |
        gum choose --header="$header" --cursor='❯ ' --height=12 |
        awk '{print $1}'
      ;;
    fzf)
      printf '%s\n' "$padded" |
        fzf --prompt="$header ❯ " --height=40% --reverse --info=inline \
            --pointer='▸' --no-multi --no-sort --ansi |
        awk '{print $1}'
      ;;
    *)
      printf '\n%s\n\n' "$header" >&2
      local line
      local -a items=()
      mapfile -t items <<<"$padded"          # keep "tag  description" as ONE item
      select line in "${items[@]}"; do
        [ -n "$line" ] || return 1
        printf '%s\n' "${line%% *}"
        return 0
      done
      return 1
      ;;
  esac
}

# ui_confirm <question>  → 0 = yes, 1 = no
ui_confirm() {
  local prompt="$1" ans
  if [ "$(ui_backend)" = gum ] && [ -t 0 ]; then
    gum confirm "$prompt"
    return
  fi
  [ -t 0 ] || return 1
  read -r -p "$prompt [y/N] " ans
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
