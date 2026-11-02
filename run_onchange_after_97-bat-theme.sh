#!/bin/sh
# bat only reads themes from its cache, so a new .tmTheme file in
# ~/.config/bat/themes is invisible until `bat cache --build` runs.
#
# Runs whenever this file changes. Harmless when bat is not installed.

command -v bat >/dev/null 2>&1 || exit 0

# Keep whatever cache location the user has configured.
bat cache --build >/dev/null 2>&1 || true

exit 0
