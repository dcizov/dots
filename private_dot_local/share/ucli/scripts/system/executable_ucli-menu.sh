#!/usr/bin/env bash
# ucli-menu.sh — the `ucli` chooser (what runs when you type `ucli` alone).
#
# `ujust` with no arguments drops you into a menu of its recipes; this is the
# same idea with the same look as the rest of ucli: `gum choose` groups first,
# then the recipes of that group with their one-line descriptions. The recipe
# list is read from `just --list`, so the menu cannot drift from the justfile.
#
# Two levels on purpose:
#   * ~45 flat rows is a wall of text, six groups is a question you can answer,
#   * the second level is where the descriptions live.
#
# `ucli --choose` still delegates to `just --choose` (fzf, type-to-filter) for
# people who want to search instead of browse.
#
# Non-interactive (piped, CI) prints `just --list` and exits 0, so nothing that
# shells out to `ucli` accidentally blocks on a menu.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

justfile="${UCLI_JUSTFILE:-$HOME/.config/ucli/justfile}"
just_dir="$(dirname "$justfile")"

if ! command -v just >/dev/null 2>&1; then
  printf 'just is not installed; run the bootstrap (install.sh) or pacman -S just\n' >&2
  exit 1
fi
if [[ ! -r "$justfile" ]]; then
  printf 'no justfile at %s\n' "$justfile" >&2
  exit 1
fi

just_list() { just --justfile "$justfile" --working-directory "$just_dir" --list; }

if ! ui_tty; then
  just_list
  exit 0
fi

# --- parse `just --list` ----------------------------------------------------
# Lines are "    [Group]" for a group header and
# "    recipe [ARGS]        # description" for a recipe. Underscore recipes are
# hidden by just itself, so anything that shows up here is public.
rows=()
while IFS=$'\t' read -r group name desc; do
  rows+=("${group}"$'\t'"${name}"$'\t'"${desc}")
done < <(just_list | awk '
  /^[[:space:]]*\[/ {
    g = $0; sub(/^[[:space:]]*\[/, "", g); sub(/\].*$/, "", g); next
  }
  /^[[:space:]]+[a-zA-Z0-9_-]+/ {
    line = $0; sub(/^[[:space:]]+/, "", line)
    name = line; sub(/[[:space:]].*$/, "", name)
    desc = ""
    if (match(line, /# /)) desc = substr(line, RSTART + 2)
    print (g == "" ? "Recipes" : g) "\t" name "\t" desc
  }')

if ((${#rows[@]} == 0)); then
  printf 'could not read the recipe list from %s\n' "$justfile" >&2
  exit 1
fi

# --- group order (first appearance, matching the justfile) -------------------
groups=()
declare -A counts=()
for row in "${rows[@]}"; do
  g="${row%%$'\t'*}"
  if [[ -z "${counts[$g]:-}" ]]; then
    groups+=("$g")
    counts[$g]=0
  fi
  counts[$g]=$(( ${counts[$g]} + 1 ))
done

ui_title "ucli"
echo

menu=()
for g in "${groups[@]}"; do
  if [[ "${counts[$g]}" == 1 ]]; then
    menu+=("${g}|1 recipe")
  else
    menu+=("${g}|${counts[$g]} recipes")
  fi
done
menu+=("list|every recipe as a plain list")
menu+=("quit|nothing, just exit")

choice="$(ui_choose "What do you want to do?" "${menu[@]}")" || exit 0

case "$choice" in
  quit|"") exit 0 ;;
  list)    show just_list; exit 0 ;;
esac

# --- second level: the recipes of that group --------------------------------
items=()
for row in "${rows[@]}"; do
  g="${row%%$'\t'*}"
  rest="${row#*$'\t'}"
  name="${rest%%$'\t'*}"
  desc="${rest#*$'\t'}"
  [[ "$g" == "$choice" ]] || continue
  items+=("${name}|${desc:-run it}")
done

if ((${#items[@]} == 0)); then
  printf 'nothing in that group\n' >&2
  exit 1
fi

recipe="$(ui_choose "$choice" "${items[@]}")" || exit 0
[[ -n "$recipe" ]] || exit 0

exec just --justfile "$justfile" --working-directory "$just_dir" "$recipe"
