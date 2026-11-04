# 00-host-spawn-guard.sh -- stop distrobox's `host-spawn` from taking stdin away
# shellcheck shell=sh
# from non-interactive login shells.
#
# distrobox puts a `host-spawn` wrapper on PATH so a command can step out of the
# container. Starting a *login* shell non-interactively (ssh host cmd, the SFTP
# subsystem, scp/rsync, VS Code Remote-SSH's server) sources /etc/profile, and
# the wrapper can grab stdin before the program that actually wants it — the
# symptom is scp hanging, rsync stalling, or a Remote-SSH connection that
# answers after a delay.
#
# Interactive shells keep the real host-spawn; non-interactive ones get a no-op
# function that shadows the binary. Nothing else is changed, so a container that
# never sees a non-interactive login shell behaves exactly as before.
#
# Sourced by /etc/profile.d for every login shell (bash, zsh, and plain sh), so
# this file is POSIX and defines nothing outside its own name.
case $- in
  *i*) ;;                                     # interactive: leave it alone
  *)
    # `eval` is deliberate: a function name containing a hyphen is not POSIX
    # syntax, and /etc/profile.d is sourced by plain sh as well — a parser that
    # never runs the branch can still choke on it. Only bash and zsh get here,
    # and only they parse the string.
    if [ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ]; then
      eval 'host-spawn() { :; }'
    fi
    ;;
esac
