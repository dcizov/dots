#!/usr/bin/env bash
# =============================================================================
# devbox-vscode-bisect.sh -- find the exact file in the `bash -l` chain that
#                            consumes stdin, and prove the fix before applying.
#
# Run ON THE HOST:   ./devbox-vscode-bisect.sh [ssh-host]     (default: dev)
#
# The trick: source ONE candidate file, then `cat` the piped payload. If the
# payload comes back, that file left stdin alone. If it comes back empty, that
# file ate it -- which is what kills open-remote-ssh, because the extension
# pipes its whole install script into `bash -l` on stdin.
# =============================================================================
set -u

HOST="${1:-dev}"
PAYLOAD='STDIN_PAYLOAD'

R()   { printf '\033[1m%s\033[0m\n' "$1"; }
ok()  { printf '  \033[32msurvived\033[0m  %s\n' "$1"; }
bad() { printf '  \033[31mATE STDIN\033[0m  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

# Sourced alone, in a throwaway shell. $HOME is expanded by the REMOTE bash.
probe() {
    printf '%s\n' "$PAYLOAD" | ssh "$HOST" "bash -c '$1 >/dev/null 2>&1; cat'" 2>/dev/null
}

R "== bisecting the bash -l profile chain on $HOST =="

# /etc/profile sources /etc/profile.d/*.sh in alphabetical order, then bash
# reads the FIRST of ~/.bash_profile, ~/.bash_login, ~/.profile.
CANDIDATES='/etc/profile
/etc/profile.d/bash_completion.sh
/etc/profile.d/distrobox_profile.sh
/etc/profile.d/vte-2.91.sh
. /etc/profile
. $HOME/.bash_profile
. $HOME/.bash_login
. $HOME/.profile
. $HOME/.bashrc'

while IFS= read -r c; do
    [ -n "$c" ] || continue
    out=$(probe ". $c")
    if [ "$out" = "$PAYLOAD" ]; then ok "$c"; else bad "$c"; fi
done <<< "$CANDIDATES"

# --- prove the fix -------------------------------------------------------------
# Defining a no-op host-spawn FUNCTION shadows the binary for the rest of the
# shell, so distrobox_profile.sh's $(host-spawn ...) calls never touch fd 0.
R "== does shadowing host-spawn fix the whole chain? =="
out=$(probe 'host-spawn() { :; }; . /etc/profile')
if [ "$out" = "$PAYLOAD" ]; then
    ok "host-spawn was the stdin eater -- the guard below fixes it"
else
    bad "still eaten -- the culprit is elsewhere, check the trace below"
fi

# --- confirm end to end, exactly like the extension ---------------------------
R "== full pipeline after the fix =="
printf '%s\n' "echo HELLO" | base64 -w0 > /tmp/.b64
out=$(ssh "$HOST" "echo $(cat /tmp/.b64) | base64 -d | bash -c 'host-spawn() { :; }; exec bash -l'" 2>&1)
note "bash -l with guard -> [${out}]"
rm -f /tmp/.b64

# --- evidence -----------------------------------------------------------------
R "== /etc/profile.d/distrobox_profile.sh (distrobox regenerates this every start) =="
ssh "$HOST" 'cat /etc/profile.d/distrobox_profile.sh 2>/dev/null' | sed 's/^/  /'

R "== xtrace of the failing case (last commands before stdin runs dry) =="
printf 'echo STDIN_MARKER_OK\n' | ssh "$HOST" 'bash -lx' 2>&1 | tail -30 | sed 's/^/  /'

R "== done =="
