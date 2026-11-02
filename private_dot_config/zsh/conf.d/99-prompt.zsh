# Prompt
#
# TODO(prompt): inside the distrobox, zle redraws one line off.
#
# Symptom: in `distrobox enter dev`, every Tab (also Enter) prints the prompt
# again one line lower and leaves the cursor mid-line; the host with the same
# config, terminal, locale and starship binary is fine. Present since starship
# was adopted.
#
# Already ruled out — do not re-investigate these:
#   * locale: both sides are multibyte UTF-8, zsh measures ${#${(%):-🌱}} == 1
#   * starship version: host and box both run 1.27.0 (/usr/local/bin)
#   * the `in ⬢ dev` badge: `env -u CONTAINER_ID zsh` in the box still jumps,
#     and glibc wcwidth() measures the prompt (with the badge) at exactly the
#     terminal width -> U+2B22 is not being miscounted
#   * broken escapes: 14 `%{` / 14 `%}`, balanced, `$line_break` outside markers
#   * inherited COLUMNS: zsh always takes the pty size, never $COLUMNS
#
# The one asymmetry left is that `$fill` + the right-aligned `$time` make the
# top line exactly as wide as the terminal (verified: 82/82 at width 82). A
# single column of disagreement between zle's count and what the terminal
# renders wraps that line and produces precisely this redraw artefact, so the
# first thing to try is taking the flush line away:
#
#   # starship.toml - candidate A: no fill, time inline before the break
#   format = '...$cmd_duration$time$line_break[╰─](dim)$python$character'
#   [fill]
#   disabled = true
#
# Other known causes of this artefact, cheapest first:
#   * bisect the shell: `zsh -f`, then `eval "$(starship init zsh)"`, then the
#     full config - which of the three already jumps in the box?
#   * completion widgets: the box has a different plugin set than the host
#     (Debian has no /usr/share/zsh/plugins/zsh-{autosuggestions,syntax-highlighting},
#     so 90-post-plugins.zsh silently loads nothing there while fzf-tab is
#     present). Try in the box: `zsh -f` + `eval "$(starship init zsh)"` +
#     `zstyle ':completion:*' menu no` and Tab.
#   * pty size inside the container: `stty size` in the box vs the host window;
#     if starship pads for 82 columns while the pty reports 80, the line wraps.
#   * `zle reset-prompt` callers (starship's keymap hook, fzf-tab, atuin) firing
#     twice - `bindkey '^I'` should show what Tab is actually bound to.

if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi
