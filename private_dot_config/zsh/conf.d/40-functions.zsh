# Functions.

bh() {
  (( $+commands[bat] )) || { "$@" --help; return; }
  "$@" --help 2>&1 | bat --language=help --style=plain --paging=always
}

tlf() {
  (( $+commands[tldr] && $+commands[fzf] )) || return
  local page
  page="$(tldr --list 2>/dev/null | fzf --prompt='tldr> ' --preview='tldr {} 2>/dev/null' --preview-window=right:60%:wrap)" || return
  [[ -n "$page" ]] && tldr "$page"
}

fe() {
  (( $+commands[fd] && $+commands[fzf] )) || return
  local file
  file="$(fd --type f --hidden --follow --exclude .git . "${1:-.}" | fzf --preview='bat --color=always --style=numbers,changes --line-range=:300 {} 2>/dev/null || file {}' --preview-window=right:60%:wrap)" || return
  [[ -n "$file" ]] && "$EDITOR" "$file"
}

cdf() {
  (( $+commands[fd] && $+commands[fzf] )) || return
  local dir
  dir="$(fd --type d --hidden --follow --exclude .git . "${1:-.}" | fzf --prompt='cd> ' --preview='eza --tree --level=2 --color=always --icons=auto --group-directories-first {} 2>/dev/null || ls -la {}' --preview-window=right:60%:wrap)" || return
  [[ -n "$dir" ]] && cd "$dir"
}

rfi() {
  (( $+commands[rg] && $+commands[fzf] )) || return
  local result file line
  result="$(rg --line-number --column --color=always --smart-case "${*:-}" | fzf --ansi --delimiter ':' --preview='bat --color=always --style=numbers,changes --highlight-line {2} --line-range {2}: {1} 2>/dev/null' --preview-window=right:60%:wrap)" || return
  file="${result%%:*}"
  line="${${result#*:}%%:*}"
  [[ -n "$file" && -n "$line" ]] && "$EDITOR" "+$line" "$file"
}

gcof() {
  (( $+commands[git] && $+commands[fzf] )) || return
  local branch
  branch="$(git branch --all --color=always | grep -v HEAD | fzf --ansi --prompt='checkout> ' | sed 's/^[* ]*//' | sed 's#remotes/origin/##')" || return
  [[ -n "$branch" ]] && git checkout "$branch"
}

pacf() {
  (( $+commands[pacman] && $+commands[fzf] )) || return
  pacman -Qqe | fzf --prompt='pkg> ' --preview='pacman -Qi {} 2>/dev/null' --preview-window=right:60%:wrap
}

fkill() {
  (( $+commands[fzf] )) || return
  local pid
  pid="$(ps -ef | sed 1d | fzf --prompt='kill> ' --preview='echo {}' --preview-window=right:60%:wrap | awk '{print $2}')" || return
  [[ -n "$pid" ]] && kill "$pid"
}

glogf() {
  (( $+commands[git] && $+commands[fzf] )) || return
  git log --graph --color=always --format='%C(auto)%h%d %s %C(black)%C(bold)%cr' "$@" |
    fzf --ansi --no-sort --reverse --prompt='git log> ' \
      --preview='commit=$(echo {} | grep -o "[a-f0-9]\{7,\}" | head -1); git show --color=always "$commit"' \
      --preview-window=right:70%:wrap
}

bat-theme() {
  (( $+commands[bat] && $+commands[fzf] )) || return
  local file="${1:-$HOME/.zshrc}"
  bat --list-themes | fzf --prompt='bat theme> ' --preview="bat --theme={} --color=always --style=numbers,changes,header '$file'"
}

batlang() {
  (( $+commands[bat] && $+commands[fzf] )) || return
  bat --list-languages | fzf --prompt='bat language> '
}

batdiff() {
  (( $+commands[git] && $+commands[bat] )) || return
  git diff --name-only --relative --diff-filter=d -z | xargs -0 bat --diff
}

batwatch() {
  (( $+commands[bat] )) || return
  [[ -n "$1" ]] || { echo 'usage: batwatch FILE'; return 2; }
  tail -f "$1" | bat --paging=never -l log
}

cleanup() {
  local pkgs
  pkgs="$(pacman -Qtdq 2>/dev/null)"
  [[ -n "$pkgs" ]] && sudo pacman -Rns ${(f)pkgs} || echo "No orphaned packages."
}
