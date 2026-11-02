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
# CAUSE (matches the symptom and the reports): `$fill` padded the first prompt
# line to EXACTLY the terminal width, and zsh mis-counts zle redraws for
# multi-line prompts whose line fills the full width -- every completion redraw
# moves one row too many, so the prompt repaints a line lower each time and
# walks up the screen. Reproduced-by-others, not a distrobox bug:
#   https://stackoverflow.com/a/23544078            ("happens exactly when the
#       first line of the prompt fully fills the width of the terminal")
#   https://github.com/sorin-ionescu/prezto/issues/1245
#   https://github.com/ohmyzsh/ohmyzsh/issues/6226
#
# FIX APPLIED: `$fill` removed from the format and `[fill] disabled = true` in
# starship.toml; `$time` is now inline. The first line ends ~37 columns short of
# the edge, so the width mismatch that used to matter (host 82 / box 80) cannot
# wrap it any more. Verify with `starship prompt --terminal-width=82 | head -1`:
# the drawn width must stay constant, not equal to the terminal width.
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
