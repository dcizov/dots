# Prompt
#
# `$fill` pads the first prompt line to EXACTLY the terminal width so the clock
# sits on the right margin. With a multi-line prompt that is a known zsh redraw
# bug: every completion redraw (Tab) moves one row too many, so the prompt is
# repainted a line lower each time and walks up the screen, eating the line
# above. It only shows when the prompt and the terminal agree to the column, so
# it was visible in the distrobox (whose pty width differed from the host's) and
# not on the host.
#   https://stackoverflow.com/a/23544078   ("happens exactly when the first line
#                                          fully fills the width of the terminal")
#   https://github.com/sorin-ionescu/prezto/issues/1245
#   https://github.com/ohmyzsh/ohmyzsh/issues/6226
#
# Fix: keep `$fill` — the clock stays where it was — but give starship a
# terminal two columns narrower than the real one, so the fill stops two columns
# short of the margin. Visually identical, and zle's row accounting stays right.
# Verified on a pty: drawn line 1 is 80 of 82 columns instead of a flush 82.

if (( $+commands[starship] )); then
  eval "$(starship init zsh)"

  # starship init bakes `--terminal-width="$COLUMNS"` into PROMPT and RPROMPT.
  if [[ $PROMPT == *'--terminal-width="$COLUMNS"'* ]]; then
    PROMPT=${PROMPT//--terminal-width=\"\$COLUMNS\"/--terminal-width=\"\$(( COLUMNS - 2 ))\"}
    RPROMPT=${RPROMPT//--terminal-width=\"\$COLUMNS\"/--terminal-width=\"\$(( COLUMNS - 2 ))\"}
  else
    print -u2 'warning: starship init no longer uses --terminal-width="$COLUMNS"'
    print -u2 '         the prompt may eat a line on Tab; see the note above'
  fi
fi
