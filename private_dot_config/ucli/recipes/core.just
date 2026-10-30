# Pick a command.
_choose:
    @ucli --choose

# Show common flows.
[group('Help')]
usage:
    @printf '%s\n' 'Day to day:'
    @printf '%s\n' '  ucli update    # pacman + AUR + flatpaks + dev box'
    @printf '%s\n' '  ucli logs      # this boot / last boot / devbox / pacman'
    @printf '%s\n' '  ucli clean-system'
    @printf '%s\n' ''
    @printf '%s\n' 'Setup:'
    @printf '%s\n' '  chezmoi init/apply'
    @printf '%s\n' '  ucli setup-snapshots'
    @printf '%s\n' '  ucli setup-system'
    @printf '%s\n' '  ucli devbox-reconcile'
    @printf '%s\n' ''
    @printf '%s\n' 'Browse commands:'
    @printf '%s\n' '  ucli --choose'
    @printf '%s\n' ''
    @printf '%s\n' 'Optional:'
    @printf '%s\n' '  ucli cli       # shell CLI experience'
    @printf '%s\n' '  ucli devmode   # developer tools'
    @printf '%s\n' '  ucli gaming    # gaming profile'
    @printf '%s\n' '  ucli apps      # personal apps and overrides'
    @printf '%s\n' '  ucli extras    # everything else: shell, paru, overrides, full setup'
    @printf '%s\n' '  ucli system    # checks and maintenance helpers'
    @printf '%s\n' '  ucli gnome     # GNOME helpers'
    @printf '%s\n' '  ucli devbox    # box menu: reconcile, shell, versions, log, recreate …'
    @printf '%s\n' ''
    @printf '%s\n' 'Direct tools:'
    @printf '%s\n' '  chezmoi diff && chezmoi apply -v'
    @printf '%s\n' '  ucli devbox-reconcile    # creates or updates the box'
    @printf '%s\n' '  ucli devbox              # menu, incl. recreate on a new Debian base'
    @printf '%s\n' '  cd ~/.config/dev-services && docker compose up -d'

# Show configured and detected profile data.
[group('Help')]
profile:
    ~/.config/ucli/scripts/system/detect.sh

# Check setup health.
[group('Help')]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "== chezmoi =="
    mkdir -p "$HOME/.cache/tmp"
    TMPDIR="$HOME/.cache/tmp" chezmoi doctor || true
    echo
    echo "== zsh =="
    zsh -n "$HOME/.zshrc"
    echo "OK: ~/.zshrc"
    echo
    echo "== commands =="
    for cmd in just chezmoi zsh git curl nano; do
      command -v "$cmd" >/dev/null 2>&1 && printf 'OK:      %s -> %s\n' "$cmd" "$(command -v "$cmd")" || printf 'MISSING: %s\n' "$cmd"
    done
    echo
    echo "== devbox =="
    if command -v distrobox >/dev/null 2>&1; then
      printf 'OK:      distrobox -> %s\n' "$(command -v distrobox)"
      if distrobox list --no-color 2>/dev/null | grep -qE '\bdev\b'; then
        # a container that exists but was never provisioned looks identical to a
        # healthy one unless we ask about the versions the tooling assumes
        # `locale charmap` is the effective charset: a LANG that names a locale
        # the container never generated still reads as ANSI_X3.4-1968, and zsh
        # then measures the prompt in bytes (prompt eats a line on every redraw).
        out="$(distrobox enter dev -- bash -lc \
          'printf "%s|%s|%s|%s\n" "$(cat /etc/debian_version)" \
             "$(node -v 2>/dev/null || echo MISSING)" \
             "$(php -r "echo PHP_VERSION;" 2>/dev/null || echo MISSING)" \
             "$(locale charmap 2>/dev/null || echo none)"' 2>/dev/null || true)"
        IFS='|' read -r debian node php charmap <<<"$out" || true
        if [[ -n "$debian" && "$node" != MISSING && "$php" != MISSING ]]; then
          printf 'OK:      dev: debian %s / node %s / php %s / locale %s\n' \
            "$debian" "$node" "$php" "${charmap:-?}"
          if [[ "${charmap:-}" != UTF-8 ]]; then
            printf 'WARN:    dev locale is %s, not UTF-8 — prompt/redraw will misbehave\n' \
              "${charmap:-unknown}"
            printf '         run: ucli devbox-reconcile  (provisions a UTF-8 locale)\n'
          fi
        else
          printf 'INCOMPLETE: dev exists but is not provisioned (node %s, php %s)\n' \
            "${node:-?}" "${php:-?}"
          printf '         run: ucli devbox-reconcile (or ucli devbox-reprovision)\n'
        fi
      else
        printf 'MISSING: container dev (ucli devbox-reconcile)\n'
      fi
    else
      printf 'MISSING: distrobox\n'
    fi

# Compare the prompt-relevant settings of the host and the dev box.
[group('Help')]
_prompt:
    #!/usr/bin/env bash
    set -euo pipefail
    # zsh draws the prompt with zle, which needs three things to agree:
    #   * a multibyte locale   — otherwise prompt width is measured in bytes,
    #   * a terminal size shared with starship's `$fill` — otherwise the first
    #     line is one column too long and wraps,
    #   * a terminfo entry for $TERM.
    # When any of these differ between host and box, zle redraws one line off.
    row() {  # <label> <term> <cols> <charmap> <multibyte> <starship>
      printf '%-6s TERM=%-16s cols=%-4s COLUMNS=%-5s locale=%-14s zsh-multibyte=%-3s starship=%s\n' \
        "$1" "${2:-unset}" "${3:-?}" "${COLUMNS:-unset}" "${4:-?}" "$5" "${6:-MISSING}"
    }
    # /dev/tty first: with stdin redirected (which is how this recipe reaches the
    # box) `tput cols` quietly returns the terminfo default of 80, which is not
    # the terminal's width and makes the comparison meaningless.
    cols_here() {
      local size cols
      size="$(stty size < /dev/tty 2>/dev/null || true)"
      cols="${size##* }"
      # a stale pty reports 0x0, which is not a width
      case "$cols" in ''|0) cols="$(tput cols 2>/dev/null || printf '?')" ;; esac
      printf '%s' "$cols"
    }
    mb_here() {  # 1 = zsh is really multibyte, 4 = it silently fell back to C
      command -v zsh >/dev/null 2>&1 || { printf 'no'; return; }
      [[ "$(zsh -fc 'print ${#${(%):-🌱}}' 2>/dev/null || echo 4)" == 1 ]] && printf 'yes' || printf 'no'
    }

    row host "${TERM:-unset}" "$(cols_here || true)" "$(locale charmap 2>/dev/null || echo '?')" \
        "$(mb_here)" "$(starship --version 2>/dev/null | head -n1 | awk '{print $2}')"

    if ! command -v distrobox >/dev/null 2>&1; then
      printf '%-6s no distrobox\n' dev
      exit 0
    fi
    if ! distrobox list --no-color 2>/dev/null | grep -qE '\bdev\b'; then
      printf '%-6s no dev box\n' dev
      exit 0
    fi
    raw="$(distrobox enter dev -- bash -s 2>/dev/null <<'PROBE' || true
    size="$(stty size < /dev/tty 2>/dev/null || true)"
    cols="${size##* }"
    case "$cols" in ''|0) cols="$(tput cols 2>/dev/null || echo '?')" ;; esac
    mb=no
    if command -v zsh >/dev/null 2>&1 &&
       [ "$(zsh -fc 'print ${#${(%):-🌱}}' 2>/dev/null || echo 4)" = 1 ]; then
      mb=yes
    fi
    term_ok=missing
    infocmp "${TERM:-}" >/dev/null 2>&1 && term_ok=ok
    printf 'UCLI-PROMPT|%s|%s|%s|%s|%s|%s|%s\n' "${TERM:-unset}" "$cols" \
      "$(locale charmap 2>/dev/null || echo '?')" "$mb" \
      "$(starship --version 2>/dev/null | head -n1 | awk '{print $2}')" "$term_ok" \
      "$(command -v starship 2>/dev/null || echo none)"
    PROBE
    )"
    # only our own line, whatever else the login files print
    box="$(printf '%s\n' "$raw" | grep '^UCLI-PROMPT|' | tail -n 1 || true)"
    IFS='|' read -r _ bterm_name bcols bchar bmb bstar bterm bstar_path <<<"$box" || true
    row dev "$bterm_name" "$bcols" "$bchar" "$bmb" "$bstar"
    printf '%-6s terminfo for %s inside the box: %s     starship: %s\n' '' \
      "${bterm_name:-unset}" "${bterm:-not checked}" "${bstar_path:-?}"

    host_star="$(starship --version 2>/dev/null | head -n1 | awk '{print $2}')"
    if [[ -n "$host_star" && -n "${bstar:-}" && "$host_star" != "$bstar" ]]; then
      printf 'WARN   starship %s on the host but %s in the box — `$fill` lays the\n' "$host_star" "$bstar"
      printf '       prompt out differently, so the older one can draw a line one\n'
      printf '       column too wide and zle then eats a line on every redraw:\n'
      printf '         ucli devbox-reconcile   (installs the host version in the box)\n'
    fi

# Validate package arrays.
[group('Help')]
validate:
    ~/.config/ucli/scripts/install/validate-packages.sh

# Show detected system facts.
_detect:
    ~/.config/ucli/scripts/system/detect.sh

# Print config paths.
_paths:
    @printf '%s\n' '~/.zshrc' '~/.config/zsh' '~/.config/ucli' \
      '~/.config/distrobox/dev.ini' '~/.config/distrobox/devbox.env' \
      '~/.config/distrobox/provision-dev.sh' \
      '~/.config/dev-services/compose.yml' '~/.local/bin/ucli' \
      '~/.local/share/chezmoi'
