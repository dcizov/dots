#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# devbox-reconcile.sh — bring THIS machine's `dev` distrobox in line with the
#                       chezmoi-managed files in ~/.config/distrobox.
#
# chezmoi-managed: edit private_dot_config/ucli/scripts/devbox/
#                  executable_devbox-reconcile.sh in the dotfiles repo.
#
# Division of labour: chezmoi applies files (this script, dev.ini, the
# provisioner, recipes). It does NOT create or provision containers. This script
# is the single entry point for that, invoked as `ucli devbox-reconcile` (and
# `ucli devbox-recreate` for a rebuild).
#
# Inputs (plain files, no templates):
#   ~/.config/distrobox/dev.ini          -> box name ([section]), Debian major (image=)
#   ~/.config/distrobox/provision-dev.sh -> content hash (marker + fingerprint)
#   ~/.config/distrobox/devbox.env       -> optional tunables (hashed too)
#
# Provisioning is driven from HERE, not from the manifest's init_hooks: the bash
# `distrobox-assemble` base64-decodes hooks and then `eval`s the whole
# `distrobox-create ... --init-hooks '<script>'` line with `set -u`, so any `$`
# or command substitution in a hook explodes. Manifest hooks are also baked in at
# create time and must not depend on packages that provisioning installs later
# (that is what killed the container with Exit 127).
#
# Env:
#   DISTROBOX_RECREATE=1   always recreate the container first (keeps $HOME)
#   DEVBOX_SKIP_WAIT=1     do not wait for distrobox-init
#   DEVBOX_INIT_TIMEOUT    seconds to wait for distrobox-init (default 300)
#   QUIET=1                only warnings + final report
# ---------------------------------------------------------------------------
set -euo pipefail

CONF_DIR="$HOME/.config/distrobox"
INI="$CONF_DIR/dev.ini"
PROV="$CONF_DIR/provision-dev.sh"
ENV_FILE="$CONF_DIR/devbox.env"

DIM=$'\033[2m'; BOLD=$'\033[1;34m'; YEL=$'\033[1;33m'; RED=$'\033[1;31m'
GRN=$'\033[2;32m'; RST=$'\033[0m'
CLR=""; [ -t 1 ] && CLR=$'\r\033[2K'   # only meaningful on a terminal
exec 3>&1   # the animated status line writes here, never into piped output

STEP_N=0; SPIN_PID=0; STATUS_LABEL=""; STATUS_T0=0; SCRIPT_T0=$SECONDS

dur() {
  local s="${1:-0}"
  if [ "$s" -ge 60 ]; then printf '%dm%02ds' $(( s / 60 )) $(( s % 60 )); else printf '%ds' "$s"; fi
}

# Outer steps are labelled "devbox:" so they never collide with the numbered
# steps the provisioner prints inside the container.
log()  { [ "${QUIET:-0}" = "1" ] && return 0
         STEP_N=$(( STEP_N + 1 ))
         printf '\n%s==> devbox: %s%s\n' "$BOLD" "$*" "$RST"; }
say()  { [ "${QUIET:-0}" = "1" ] || printf '    %s%s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s[warn]%s %s\n' "$YEL" "$RST" "$*" >&2; }
die()  {
  if [ "$SPIN_PID" != "0" ]; then
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=0
    printf '%s' "$CLR"
  fi
  printf '%s[error]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1;
}

# one status line, redrawn in place while a host-side command runs
status_start() {
  STATUS_LABEL="$1"; STATUS_T0=$SECONDS
  printf '    %s▸ %s%s\n' "$DIM" "$1" "$RST"
  [ -t 1 ] || return 0
  { : >&3; } 2>/dev/null || return 0
  (
    set +e
    case "${DEVBOX_SPINNER:-bar}" in
      braille)       frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' ;;
      static-char:*) frames="${DEVBOX_SPINNER#static-char:}" ;;
      *)             frames='|/-\' ;;
    esac
    nframes=${#frames}; i=0
    while :; do
      printf '%s    %s%s %s%s' "$CLR" "$DIM" "${frames:$(( i % nframes )):1}" "$(dur $(( SECONDS - STATUS_T0 )))" "$RST" >&3
      i=$(( i + 1 )); sleep 0.1
    done
  ) &
  SPIN_PID=$!
}
status_stop() {
  local mark="${1:-}" took
  if [ "$SPIN_PID" != "0" ]; then
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=0
    printf '%s' "$CLR"
  fi
  [ -n "$mark" ] || return 0
  took="$(dur $(( SECONDS - STATUS_T0 )))"
  case "$mark" in
    ok)   printf '    %s✓%s %s%s · %s%s\n' "$GRN" "$RST" "$DIM" "$STATUS_LABEL" "$took" "$RST" ;;
    fail) printf '    %s✗ %s · %s%s\n' "$RED" "$STATUS_LABEL" "$took" "$RST" ;;
  esac
}

# Run a host-side command the way `docker build` prints RUN steps: the label
# dimmed, its output dimmed and indented, streamed.
# Turn a raw log stream into something readable: drop shell traces (`set -x`
# output, and the continuation lines of multi-line assignments), blank lines and
# consecutive duplicates. Everything else is dimmed and indented as it arrives.
# DEVBOX_TRACE=1 shows the untouched stream.
narrate() {
  if [ "${DEVBOX_TRACE:-0}" = "1" ]; then
    sed -u -e 's/\r$//' -e "s/^/    ${DIM}│${RST} /"
    return 0
  fi
  awk -v dim="$DIM" -v rst="$RST" -v clr="$CLR" '
    { sub(/\r$/, "") }
    /^\+\+? / { cont = ($0 ~ /=$/) ; next }
    cont && /^[ \t][ \t]+/ { next }
    { cont = 0 }
    /^[ \t]*$/ { next }
    $0 == prev { next }
    { prev = $0; printf "%s    %s│%s %s\n", clr, dim, rst, $0; fflush() }
  '
}

STDBUF=""
command -v stdbuf >/dev/null 2>&1 && STDBUF="stdbuf -oL -eL"

run_dim() {
  local label="$1" rc=0; shift
  local -a pre=()
  # stdbuf exec()s its argument, so only wrap real executables, never functions
  [ -n "$STDBUF" ] && [ "$(type -t "$1" 2>/dev/null)" = "file" ] && pre=($STDBUF)
  status_start "$label"
  set +e
  "${pre[@]}" "$@" 2>&1 | narrate
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" -eq 0 ]; then status_stop ok; else status_stop fail; fi
  return "$rc"
}

command -v distrobox >/dev/null 2>&1 || { log "distrobox not installed — skipping"; exit 0; }

# One reconcile at a time per box: two concurrent runs (e.g. a leftover
# `chezmoi apply` and `ucli devbox-recreate`) would otherwise fight over apt.
if [ "${DEVBOX_LOCKED:-0}" != "1" ] && command -v flock >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/state"
  export DEVBOX_LOCKED=1
  exec flock -w 900 "$HOME/.local/state/distrobox-dev.lock" "$0" "$@"
fi
[ -f "$INI" ]  || die "missing $INI (run 'chezmoi apply' first)"
[ -f "$PROV" ] || die "missing $PROV (run 'chezmoi apply' first)"

# --- derived from files, not from the environment ---------------------------
BOX="$(sed -n 's/^\[\([^]]*\)\].*/\1/p' "$INI" | head -1)"
WANT_MAJOR="$(sed -n 's/^image=debian:\([0-9][0-9]*\).*/\1/p' "$INI" | head -1)"
[ -n "$BOX" ] || die "no [section] found in $INI"
[ -n "$WANT_MAJOR" ] || warn "image= is not 'debian:<N>' — Debian-major checks disabled"

[ "${DEVBOX_VERBOSE:-1}" = "0" ] && QUIET=${QUIET:-1}
DEVBOX_VERBOSE="${DEVBOX_VERBOSE:-1}"

PROV_HASH="$(sha256sum "$PROV" | cut -c1-8)"
INI_HASH="$(sha256sum "$INI" | cut -c1-12)"
PROV_FP="$(sha256sum "$PROV" | cut -c1-12)"
ENV_FP=""
[ -f "$ENV_FILE" ] && ENV_FP="-$(sha256sum "$ENV_FILE" | cut -c1-12)"
FP_CURRENT="${INI_HASH}-${PROV_FP}${ENV_FP}"
FP_FILE="$HOME/.local/state/distrobox-$BOX.fingerprint"

# Container manager for the BOX is whatever distrobox uses — on this host that is
# podman. docker is a different thing here: it runs the dev-services compose file
# on the host, and inside the box `docker` is the distrobox-host-exec shim that
# talks to the host daemon. Never inspect/remove the box with docker.
CM="${DISTROBOX_CONTAINER_MANAGER:-}"
if [ -z "$CM" ]; then
  for CONF in "$HOME/.config/distrobox/distrobox.conf" /etc/distrobox/distrobox.conf; do
    [ -r "$CONF" ] || continue
    cm_line="$(sed -n 's/^[[:space:]]*container_manager[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONF" | head -1)"
    [ -n "$cm_line" ] && CM="$cm_line" && break
  done
fi
if [ -z "$CM" ]; then
  if   command -v podman >/dev/null 2>&1; then CM=podman
  elif command -v docker >/dev/null 2>&1; then CM=docker
  else die "neither podman nor docker found"
  fi
fi
command -v "$CM" >/dev/null 2>&1 || die "container manager '$CM' (from distrobox config) not found"

box_exists()  { "$CM" inspect "$BOX" >/dev/null 2>&1; }
box_running() { [ -n "$("$CM" ps -q --filter "name=^${BOX}$" 2>/dev/null)" ]; }
container_status() { "$CM" inspect -f '{{.State.Status}}' "$BOX" 2>/dev/null || true; }

container_logs_tail() { "$CM" logs --tail 20 "$BOX" 2>&1 | sed 's/^/  | /' || true; }

# Start the container and fail fast — with the container's own log — when its
# entrypoint (distrobox-init) dies immediately, e.g. a failing init hook.
ensure_running() {
  box_running && return 0
  "$CM" start "$BOX" >/dev/null 2>&1 || true
  local i=0
  for i in $(seq 1 30); do
    box_running && return 0
    case "$(container_status)" in
      exited|dead)
        printf '\033[1;31merror:\033[0m container %s failed to stay running (status: %s)\n' \
          "$BOX" "$(container_status)" >&2
        printf 'last lines of the container log:\n' >&2
        container_logs_tail >&2
        die "the container's init hook or entrypoint is failing; fix $INI, then: distrobox rm -f $BOX && $0"
        ;;
    esac
    sleep 1
  done
  return 1
}
in_box() { "$CM" exec -u 0 "$BOX" "$@"; }

# NOTE: the container runs with --pid host (distrobox does that when init=false
# and unshare_process is off), so /proc/1 inside it is the HOST's init and
# `pgrep apt-get` sees every host process. Anything keyed on those is unreliable;
# the only dependable signal is the marker distrobox-init prints when it is done.
container_busy() { return 1; }

# busy = distrobox-init has not printed container_setup_done yet. That marker is
# printed once, at the very end of init, so it cannot be faked by a gap between
# two apt calls (which is what made the old heuristic hand the dpkg lock to us
# and kill the container).
init_still_running() {
  ! "$CM" logs "$BOX" 2>/dev/null | grep -q container_setup_done
}

# distrobox-create returns while distrobox-init is still installing
# `additional_packages`; apt-get from here during that window fails with
# "E: Could not get lock /var/lib/apt/lists/lock". Wait, but never look hung:
# progress every ~10 s, hard cap, and bail out early if the container is gone.
INIT_READY=0; WAIT_DONE=0
wait_for_init_ready() {
  # called up to three times on the slow path; only the first one may wait and
  # stream — including when that first attempt times out
  [ "$WAIT_DONE" = "1" ] && return 0
  local timeout="${DEVBOX_INIT_TIMEOUT:-300}" deadline fails=0 elapsed=0
  local logfile seen=0 new_lines=0
  [ "${DEVBOX_SKIP_WAIT:-0}" = "1" ] && return 0
  box_running || return 0

  WAIT_DONE=1
  logfile="$(mktemp "${TMPDIR:-/tmp}/devbox-init.XXXXXX")"
  # NOTE: no `trap ... RETURN` here — RETURN traps are not function-local, they
  # fire when *any* function returns, and `set -u` then kills the shell on an
  # unset `logfile` in the caller. Clean up explicitly at each exit instead.
  # Echo distrobox-init's own progress as it arrives: locale-gen and the
  # additional_packages install can take a while on a cold container, and a
  # silent wait looks like a hang.

  deadline=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    "$CM" logs "$BOX" >"$logfile" 2>&1 || : 
    new_lines="$(wc -l <"$logfile")"
    if [ "$new_lines" -gt "$seen" ] && [ "$DEVBOX_VERBOSE" = "1" ]; then
      sed -n "$(( seen + 1 )),${new_lines}p" "$logfile" | narrate
    fi
    seen="$new_lines"
    if grep -q container_setup_done "$logfile"; then
      rm -f "$logfile"
      INIT_READY=1
      return 0
    fi
    if ! box_running; then
      warn "container '$BOX' stopped while waiting for distrobox-init"
      rm -f "$logfile"
      return 0
    fi
    elapsed=$(( $(date +%s) - (deadline - timeout) ))
    if [ "$elapsed" -ge 10 ] && [ $(( elapsed % 20 )) -lt 4 ]; then
      printf '    %s… still installing ca-certificates curl sudo (%ss, giving up at %ss) - Ctrl-C is safe here%s\n' \
        "$DIM" "$elapsed" "$timeout" "$RST"
    fi
    sleep 3
  done
  warn "distrobox-init in '$BOX' still busy after ${timeout}s - last output:"
  tail -n 10 "$logfile" | sed -u -e 's/\r$//' -e 's/^/    /' >&2 || true
  rm -f "$logfile"
  return 1
}

console_debian_major() {
  in_box sh -c 'cut -d. -f1 /etc/debian_version' 2>/dev/null | tr -d '\r' || true
}

# Recreate the container and PROVE it happened.
#
# `distrobox assemble create --replace` cannot be trusted: in distrobox <= 1.8.x
# a `replace=` line in the manifest overrides the CLI flag, so it prints
# "dev already exists" and still exits 0. Removing the container first is
# deterministic on both the bash and the Go implementations.
recreate_box() {
  local old_major="${1:-?}" new_major=""
  log "recreating '$BOX': Debian $old_major -> ${WANT_MAJOR:-?} (container discarded, \$HOME kept)"
  run_dim "distrobox rm --force $BOX" distrobox rm --force "$BOX" \
    || run_dim "$CM rm -f $BOX" "$CM" rm -f "$BOX" || true
  box_exists && die "could not remove container '$BOX' — try: $CM rm -f $BOX"
  run_dim "distrobox assemble create --file $INI" distrobox assemble create --file "$INI"
  ensure_running || die "could not start '$BOX' after recreate"
  log "waiting for distrobox-init (installs ca-certificates curl sudo, ~10-60 s)"
  wait_for_init_ready || die "distrobox-init did not complete in '$BOX' — check container logs"
  new_major="$(console_debian_major)"
  if [ -n "$WANT_MAJOR" ] && [ -n "$new_major" ] && [ "$new_major" != "$WANT_MAJOR" ]; then
    die "recreate did not take effect: container reports Debian $new_major, $INI asks for $WANT_MAJOR"
  fi
  log "recreated on Debian ${new_major:-?}"
  rm -f "$FP_FILE.pending"
}

provision_in_box() {
  # $PROV is the host path and the same absolute path inside the container
  # ($HOME is bind-mounted), so there is no /opt/devbox copy any more: the old
  # second attempt only masked the first error (it failed with exit 127).
  # DEVBOX_VERBOSE=1 makes provision-dev.sh stream every command dimmed and
  # indented (docker-build style); provisioning is a child of this process, so a
  # tty on stdout is visible to it.
  # `podman exec` gives the child no tty, so tell the provisioner explicitly to
  # stream (docker-build style). DEVBOX_VERBOSE=0 / QUIET=1 silences it.
  ANIM=0; [ -t 1 ] && ANIM=1
  # the box must draw the prompt with the same starship the host uses: the $fill
  # layout differs between versions, and a line one column too wide wraps, which
  # makes zle eat a line on every redraw inside the box only
  # first line only, and only if it really is a version: `starship --version` on
  # this host also emits trailing lines, and an unvalidated capture ends up in the
  # installer command line ("sh: 4: 10:19:51: not found").
  STARSHIP_VERSION="$(command -v starship >/dev/null 2>&1 \
    && starship --version 2>/dev/null | head -n1 | awk '{print $2}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
  # the box needs to generate the HOST's locale (a container that was entered
  # with LC_ALL=de_DE.UTF-8 but never generated it keeps warning about it)
  DEVBOX_LOCALE="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  if ! in_box env DEVBOX_PROVISION_HASH="$PROV_HASH" DEVBOX_VERBOSE="$DEVBOX_VERBOSE" \
       STARSHIP_VERSION="$STARSHIP_VERSION" DEVBOX_LOCALE="$DEVBOX_LOCALE" \
       DEVBOX_ANIM="$ANIM" ${DEVBOX_FORCE:+DEVBOX_FORCE="$DEVBOX_FORCE"} \
       /usr/bin/env bash "$PROV"; then
    printf '\033[1;31merror:\033[0m provisioning failed in %s\n' "$BOX" >&2
    in_box sh -c 'tail -n 25 /var/log/devbox-provision.log 2>/dev/null' >&2 || true
    if ! box_running; then
      printf 'the container is no longer running (status: %s); its log:\n' "$(container_status)" >&2
      container_logs_tail >&2
      die "recreate it with: ucli devbox-recreate"
    fi
    die "full log: distrobox enter $BOX -- sudo tail -50 /var/log/devbox-provision.log"
  fi
}

mkdir -p "$(dirname "$FP_FILE")"
FP_OLD="$(cat "$FP_FILE" 2>/dev/null || true)"

# --- fast path ---------------------------------------------------------------
FAST=1
[ "$FP_OLD" = "$FP_CURRENT" ] || FAST=0
box_exists || FAST=0
[ "${DISTROBOX_RECREATE:-0}" = "1" ] && FAST=0
if [ "$FAST" = "1" ]; then
  if [ -n "$WANT_MAJOR" ] && box_running; then
    cur_major="$(console_debian_major)"
    if [ -n "$cur_major" ] && [ "$cur_major" != "$WANT_MAJOR" ]; then
      printf '%s\n' "$cur_major" >"$FP_FILE.pending"
    fi
  fi
  if [ -f "$FP_FILE.pending" ]; then
    warn "'$BOX' is still on Debian $(cat "$FP_FILE.pending"), $INI asks for $WANT_MAJOR."
    warn "Rebuild it when convenient:  ucli devbox-recreate"
  fi
  exit 0
fi

# --- create / recreate / start ----------------------------------------------
if ! box_exists; then
  log "creating box '$BOX' (Debian ${WANT_MAJOR:-?})"
  run_dim "distrobox assemble create --file $INI" distrobox assemble create --file "$INI"
  ensure_running || die "could not start container '$BOX'"
  log "waiting for distrobox-init (installs ca-certificates curl sudo, ~10-60 s)"
  wait_for_init_ready
elif [ "${DISTROBOX_RECREATE:-0}" = "1" ]; then
  # a stopped/broken container cannot be queried for its version
  old_major="$(console_debian_major)"
  recreate_box "${old_major:-?}"
fi

ensure_running || die "could not start container '$BOX'"
say "container manager: ${CM} (docker on this host is for dev-services; inside the box it is the host-exec shim)"

actual_major="$(console_debian_major)"
if [ -n "$actual_major" ] && [ -n "$WANT_MAJOR" ] && [ "$actual_major" != "$WANT_MAJOR" ]; then
  warn "box '$BOX' runs Debian $actual_major, $INI asks for $WANT_MAJOR."
  warn "Container state (apt packages) is discarded on recreate; \$HOME, nvm,"
  warn "your repos and ~/.config survive. Then:"
  warn "    ucli devbox-recreate"
  warn "  or: DISTROBOX_RECREATE=1 chezmoi apply --force"
  printf '%s\n' "$actual_major" >"$FP_FILE.pending"
fi

# --- provision ---------------------------------------------------------------
wait_for_init_ready || die "distrobox-init did not complete in '$BOX' — check container logs"
log "provisioning '$BOX' (script hash $PROV_HASH — no-op unless it changed)"
provision_in_box

if [ -n "$FP_OLD" ] && [ "${FP_OLD%%-*}" != "${FP_CURRENT%%-*}" ] && [ ! -f "$FP_FILE.pending" ]; then
  warn "dev.ini changed since '$BOX' was created — image/volumes/init_hooks only land on recreate"
  say "→  ucli devbox-recreate   (or DISTROBOX_RECREATE=1 chezmoi apply --force)"
fi
printf '%s\n' "$FP_CURRENT" >"$FP_FILE"

log "state of '$BOX'"
in_box sh -c 'printf "  debian:   %s\n" "$(cat /etc/debian_version)"' || true
in_box su -l "$(id -un 1000)" -s /bin/bash -c \
  'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" 2>/dev/null; printf "  node:     %s\n  npm:      %s\n" "$(node -v 2>/dev/null)" "$(npm -v 2>/dev/null)"' || true
in_box sh -c 'printf "  php:      %s\n" "$(php -v 2>/dev/null | head -1)"; printf "  composer: %s\n" "$(composer --version 2>/dev/null)"' || true

[ "${QUIET:-0}" = "1" ] || printf '\n%s==> devbox: ready in %s%s\n' "$GRN" "$(dur $(( SECONDS - SCRIPT_T0 )))" "$RST"
