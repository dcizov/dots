#!/usr/bin/env bash
# =============================================================================
# devbox-vscode-doctor.sh -- why open-remote-ssh cannot bootstrap the `dev` box
#
# Run ON THE HOST:   ./devbox-vscode-doctor.sh [ssh-host]     (default: dev)
#
# Background. jeanp413/open-remote-ssh does NOT use the system ssh client. It
# speaks SSH itself (bundled ssh2) and installs the server with one hardcoded
# remote command -- src/serverSetup.ts:340, identical in v0.4.0, v0.4.1-beta.4
# and master:
#
#     conn.exec(`echo ${base64Script} | base64 -d | bash -l`)
#
# sshd runs that through YOUR LOGIN SHELL as `<shell> -c '...'`, and `bash -l`
# then sources /etc/profile plus the first of ~/.bash_profile, ~/.bash_login,
# ~/.profile. Distrobox shares $HOME with the host, so those are your ARCH
# files being read by DEBIAN's bash.
#
# Your log shows empty stdout AND no stderr line (the extension only logs
# stderr when non-empty) and returns in ~130 ms -- too fast to have downloaded
# anything. So the script produced nothing at all. exec() in sshConnection.ts
# never checks the exit status, so a silent non-zero exit looks exactly like
# this. The tests below walk that chain and stop at the first broken layer.
# =============================================================================
set -u

HOST="${1:-dev}"
MARKER_B64='ZWNobyBIRUxMTwo='   # printf 'echo HELLO\n' | base64 -w0

R() { printf '\033[1m%s\033[0m\n' "$1"; }
ok() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
note() { printf '        %s\n' "$1"; }

R "== target: ssh $HOST =="

# --- 1. transport + auth ------------------------------------------------------
R "1. ssh transport and publickey auth"
if out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>&1); then
    ok "ssh $HOST true"
else
    bad "ssh $HOST true"
    note "$out"
    note "Stop here: nothing below matters until plain ssh works."
    exit 1
fi

# --- 2. which shell sshd uses -------------------------------------------------
# sshd always runs remote commands as: <login-shell> -c '<command>'
R "2. login shell sshd will use (container /etc/passwd, not the host's)"
shell=$(ssh "$HOST" 'getent passwd "$(id -un)" | cut -d: -f7')
note "shell = ${shell:-<empty>}"
if [ -n "$shell" ] && ssh "$HOST" "[ -x '$shell' ]"; then
    ok "$shell exists and is executable in the box"
else
    bad "$shell is missing or not executable in the box"
    note "Distrobox copies the host shell path into the container passwd entry."
    note "Arch zsh is /usr/bin/zsh; install zsh in the box or point the entry at /bin/bash."
fi

# --- 3. plain exec ------------------------------------------------------------
R "3. plain remote exec (no bash, no profile)"
out=$(ssh "$HOST" 'uname -s' 2>&1)
[ "$out" = "Linux" ] && ok "uname -s -> Linux" || bad "uname -s -> [$out] (expected Linux)"

# --- 4. server prerequisites --------------------------------------------------
# code.visualstudio.com/docs/remote/linux: openssh-server, bash, curl|wget, tar
R "4. prerequisites inside the box"
ssh "$HOST" 'for c in bash base64 tar flock curl wget ps uname; do
               printf "  %-8s %s\n" "$c" "$(command -v "$c" 2>/dev/null || echo MISSING)"
             done'
ssh "$HOST" 'printf "  glibc     %s\n" "$(ldd --version 2>/dev/null | head -1)"'

# --- 5. THE decisive test -----------------------------------------------------
# Exactly the extension's pipeline, A/B against a non-login bash.
R "5. open-remote-ssh pipeline:  echo <b64> | base64 -d | bash -l"
a=$(ssh "$HOST" "echo $MARKER_B64 | base64 -d | bash -l" 2>&1)
b=$(ssh "$HOST" "echo $MARKER_B64 | base64 -d | bash"   2>&1)
note "with    -l  -> [${a}]"
note "without -l  -> [${b}]"
if [ "$a" = "HELLO" ]; then
    ok "login bash runs a piped script correctly"
    note "Profile chain is clean. The failure is further down (step 7/8)."
elif [ "$b" = "HELLO" ]; then
    bad "\`bash -l\` is the broken layer -- your login profile chain kills it"
    note "This is the root cause. bash -l reads /etc/profile then the first of"
    note "~/.bash_profile, ~/.bash_login, ~/.profile -- your ARCH files, in Debian."
    note "Either they print, they exec, or they consume the piped script from stdin."
    note "Go to step 6 to find which one."
else
    bad "even plain \`bash\` produces nothing -- base64/bash/pipeline level problem"
    note "Check step 4 output above for MISSING entries."
fi

# --- 6. which profile file is responsible -------------------------------------
R "6. files bash -l reads, and what they do"
ssh "$HOST" 'for f in /etc/profile ~/.bash_profile ~/.bash_login ~/.profile /etc/profile.d/*.sh; do
               [ -e "$f" ] && printf "  present  %s\n" "$f"
             done'
note "-- script via -c (does NOT use stdin): --"
ssh "$HOST" 'bash -l -c "echo PROFILE_CHAIN_SURVIVED"' 2>&1 | sed 's/^/  /'
note "-- script via stdin (what the extension does): --"
printf 'echo STDIN_SURVIVED\n' | ssh "$HOST" 'bash -l' 2>&1 | sed 's/^/  /'
note "-- lines that can break a non-interactive login shell: --"
ssh "$HOST" 'grep -nHE "^[^#]*(\bexec\b|\bread\b|\bfzf\b|neofetch|figlet|fastfetch|\bbash\b|\bzsh\b)" \
               /etc/profile ~/.bash_profile ~/.bash_login ~/.profile 2>/dev/null' | sed 's/^/  /'
note "A guard at the top of ~/.bashrc keeps non-interactive shells out:"
note '    case $- in *i*) ;; *) return ;; esac'

# --- 7. sshd settings the extension requires ----------------------------------
R "7. sshd config (open-remote-ssh requires AllowTcpForwarding yes)"
ssh "$HOST" 'sudo sshd -T 2>/dev/null | grep -Ei "^(allowtcpforwarding|permitopen|allowstreamlocalforwarding|usepam|permitrootlogin)"' | sed 's/^/  /'

# --- 8. lockfile target -------------------------------------------------------
# TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"; then `exec 9<>"$TMP_DIR/server_install.lock"`
# If XDG_RUNTIME_DIR is inherited from the host but absent in the box, bash dies.
R "8. install-lock directory (XDG_RUNTIME_DIR leak from the host)"
ssh "$HOST" 'd="${XDG_RUNTIME_DIR:-/tmp}"
             printf "  XDG_RUNTIME_DIR=[%s]\n" "${XDG_RUNTIME_DIR:-unset}"
             printf "  lock dir       =[%s]\n" "$d"
             if [ -d "$d" ] && [ -w "$d" ]; then echo "  writable: yes"
             else echo "  writable: NO -- bash exec 9<>... would abort the script"; fi'

# --- 9. leftovers in the shared home ------------------------------------------
R "9. stale server install (HOME is shared with the host)"
ssh "$HOST" 'ls -ld ~/.vscodium-server ~/.vscodium-server/bin/* 2>/dev/null | sed "s/^/  /"'
note "Reset with:  ssh $HOST 'rm -rf ~/.vscodium-server'"

# --- 10. release reachable ----------------------------------------------------
R "10. can the box fetch the VSCodium REH tarball"
ssh "$HOST" 'curl -sIL -o /dev/null -w "  HTTP %{http_code}\n" \
  https://github.com/VSCodium/vscodium/releases/download/1.140.06880/vscodium-reh-linux-x64-1.140.06880.tar.gz'

R "== done =="
