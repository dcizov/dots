#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# provision-dev.sh — idempotent provisioning for the `dev` distrobox
#                    (Debian 12 bookworm / 13 trixie / 14 forky, rootless)
#
# chezmoi-managed: edit private_dot_config/distrobox/executable_provision-dev.sh
# in the dotfiles repo, never the copy under ~/.config/distrobox/.
#
# Runs as ROOT inside the container (invoked by the devbox reconcile script via
# `podman exec`; distrobox init hooks would run as root with HOME=/root, which is
# one of the reasons provisioning happens here instead).
#
# Output: when stdout is a terminal you get a `docker build`-style transcript —
# every step as a bold banner and its command output dimmed and indented, live.
#   DEVBOX_VERBOSE=1  force streaming even when not on a tty
#   DEVBOX_QUIET=1    banners only (old behaviour)
#   DEVBOX_TRACE=1    keep shell traces / blank lines in the streamed output
#
# Every run does the cheap idempotent steps (sshd, docker shim, /etc/profile.d
# bits, host-spawn guard) and then bails out when this script's content hash
# already has a marker, unless DEVBOX_FORCE=1.
#
# Tunables also come from ~/.config/distrobox/devbox.env:
#   NODE_CHANNEL (lts|22|24|26)   PHP_BRANCH (8.2…8.5)
#   DEVBOX_SKIP_APT_TOOLING=1     skip the cosmetic package list
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# output: docker-build style. Blue step banners, muted (dim) command output that
# streams live, and one status line that animates while a command runs, then
# reports how long it took. Everything is appended to a plain-text log.
#
#   DEVBOX_VERBOSE=1  stream command output (implied on a tty)
#   DEVBOX_QUIET=1    banners only
#   DEVBOX_ANIM=0     no spinner / in-place updates (for dumb terminals, CI)
#   DEVBOX_SPINNER=braille|dots|bar   spinner style (default: bar, plain ASCII)
#   DEVBOX_TRACE=1    keep shell traces and blank lines in the stream
# ---------------------------------------------------------------------------
DIM=$'\033[2m'; BOLD=$'\033[1;34m'; YEL=$'\033[1;33m'; RED=$'\033[1;31m'
GRN=$'\033[2;32m'; RST=$'\033[0m'; CLR=$'\r\033[2K'

exec 3>&1   # the animation writes here: visible, never in the log

V="${DEVBOX_VERBOSE:-0}"
[ -t 1 ] && [ "${DEVBOX_QUIET:-0}" != "1" ] && V=1
ANIM="${DEVBOX_ANIM:-0}"
[ -t 1 ] && ANIM=1
STEP_N=0
SPIN_PID=0
STATUS_LABEL=""
STATUS_T0=0
SCRIPT_T0=$SECONDS

dur() {  # 42 -> "42s", 100 -> "1m40s"
  local s="${1:-0}"
  if [ "$s" -ge 60 ]; then printf '%dm%02ds' $(( s / 60 )) $(( s % 60 )); else printf '%ds' "$s"; fi
}

step() {
  STEP_N=$(( STEP_N + 1 ))
  printf '\n%s==> [%s] %s%s\n' "$BOLD" "$STEP_N" "$*" "$RST"
}
say()  { printf '    %s%s%s\n' "$DIM" "$*" "$RST"; }
note() { printf '    %s· %s%s\n' "$DIM" "$*" "$RST"; }
warn() { printf '%s[warn]%s %s\n' "$YEL" "$RST" "$*" >&2; }
fail() { printf '%s[error]%s %s\n' "$RED" "$RST" "$*" >&2; }

# one line, redrawn in place while the command runs
status_start() {
  STATUS_LABEL="$1"; STATUS_T0=$SECONDS
  printf '    %s▸ %s%s\n' "$DIM" "$1" "$RST"
  [ "$ANIM" = "1" ] && [ "$V" = "1" ] || return 0
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

status_stop() {  # $1 = ok|fail|"" (silent)
  local mark="${1:-}" took
  if [ "$SPIN_PID" != "0" ]; then
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true   # a killed child exits 143: never let set -e see it
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

# narrate — turn a raw stream into readable lines: strip CRs, shell traces
# (`+ cmd`) and the continuation lines of multi-line assignments, drop blanks
# and immediate repeats, then dim + indent. Clears the status line first.
narrate() {
  local clr=""; [ "$ANIM" = "1" ] && clr="$CLR"
  if [ "${DEVBOX_TRACE:-0}" = "1" ]; then
    sed -u -e 's/\r$//' -e "s/^/    ${DIM}│${RST} /"
    return 0
  fi
  awk -v dim="$DIM" -v rst="$RST" -v clr="$clr" '
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

# run <label> <cmd...> — streams the command's output dimmed + indented while
# verbose, keeps the status line moving, discards output otherwise.
# Commands are wrapped in stdbuf: piped, apt/dpkg block-buffer 4 kB and you see
# nothing until the step ends; line-buffered they print as they go.
run() {
  local label="$1"; shift
  local rc=0
  status_start "$label"
  if [ "$V" = "1" ]; then
    # stdbuf exec()s its argument, so it can only wrap a real executable:
    # `stdbuf apt_get …` fails with "failed to run command 'apt_get'".
    local -a pre=()
    if [ -n "$STDBUF" ] && [ "$(type -t "$1" 2>/dev/null)" = "file" ]; then
      pre=($STDBUF)
    fi
    set +e
    "${pre[@]}" "$@" 2>&1 | narrate
    rc=${PIPESTATUS[0]}
    set -e
  else
    set +e
    "$@" >/dev/null 2>&1
    rc=$?
    set -e
  fi
  if [ "$rc" -eq 0 ]; then status_stop ok; else status_stop fail; fi
  return "$rc"
}

# plain-text transcript, ANSI stripped, for "what happened" after the fact
LOG="${DEVBOX_LOG:-/var/log/devbox-provision.log}"
strip_ansi() { sed -u -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\r//g' -e '/^[[:space:]]*$/d'; }
if : >>"$LOG" 2>/dev/null; then
  exec > >(tee >(strip_ansi >>"$LOG")) 2>&1
else
  LOG=""
fi

summary() {
  [ "${DEVBOX_QUIET:-0}" = "1" ] && return 0
  printf '\n%s==> done: %s steps in %s%s\n' "$BOLD" "$STEP_N" "$(dur $(( SECONDS - SCRIPT_T0 )))" "$RST"
  [ -n "$LOG" ] && printf '    %s· log: %s%s\n' "$DIM" "$LOG" "$RST"
}
trap 'rc=$?; [ "$rc" -ne 0 ] && { status_stop; printf "\n%s==> failed in step [%s] after %s%s\n" "$RED" "$STEP_N" "$(dur $(( SECONDS - SCRIPT_T0 )))" "$RST"; [ -n "$LOG" ] && printf "    %s· log: %s%s\n" "$DIM" "$LOG" "$RST"; }' EXIT

# ---------------------------------------------------------------------------
# 0. root check, the real (non-root) user
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { fail "must run as root inside the container"; exit 1; }

DEV_USER="${DEV_USER:-$(id -un 1000 2>/dev/null || true)}"
if [ -z "$DEV_USER" ] || [ "$DEV_USER" = root ]; then
  DEV_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }')"
fi
[ -n "$DEV_USER" ] || { fail "could not determine the container user"; exit 1; }
DEV_HOME="$(getent passwd "$DEV_USER" | cut -d: -f6)"
DEV_GROUP="$(id -gn "$DEV_USER")"
as_user() { $STDBUF su -l "$DEV_USER" -s /bin/bash -c "$1"; }

DEBIAN_MAJOR="$(cut -d. -f1 /etc/debian_version 2>/dev/null || echo "")"
# shellcheck disable=SC1091
. /etc/os-release
SURY_SUITE="${VERSION_CODENAME:-bookworm}"

ENV_FILE="$DEV_HOME/.config/distrobox/devbox.env"
# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] && . "$ENV_FILE"
NODE_CHANNEL="${NODE_CHANNEL:-lts}"
PHP_BRANCH="${PHP_BRANCH:-8.5}"

SELF="${DEVBOX_SELF:-$0}"
SELF_HASH="$(sha256sum "$SELF" 2>/dev/null | cut -c1-8 || true)"
: "${SELF_HASH:=manual}"
MARKER="/var/tmp/devbox-provisioned.${DEVBOX_PROVISION_HASH:-$SELF_HASH}"

step "container: Debian ${DEBIAN_MAJOR:-?} as user ${DEV_USER} (${DEV_HOME})"
say "script hash ${DEVBOX_PROVISION_HASH:-$SELF_HASH} · node ${NODE_CHANNEL} · php ${PHP_BRANCH}"
[ "$V" = "1" ] || say "output suppressed — DEVBOX_VERBOSE=1 to stream command output"

export DEBIAN_FRONTEND=noninteractive
# distrobox-init may still hold the apt/dpkg locks; wait instead of failing.
# DPkg::Use-Pty=0 keeps dpkg line-based when there is no tty (otherwise it
# tries to drive a pty and interleaves escape sequences); Progress-Fancy off for
# the same reason. Together with stdbuf in run(), output appears as it happens.
APT_OPTS="-o DPkg::Lock::Timeout=600 -o Dpkg::Use-Pty=0 -o Dpkg::Progress-Fancy=0 -o APT::Color=0"
apt_get() { $STDBUF apt-get $APT_OPTS "$@"; }
APT_Q="-qq"; [ "$V" = "1" ] && APT_Q="-q"

# ---------------------------------------------------------------------------
# 1. cheap idempotent steps: every run, before the marker check
# ---------------------------------------------------------------------------
GUARD_SRC=""
for cand in "$DEV_HOME/.config/distrobox/files/00-host-spawn-guard.sh" \
            /opt/devbox/00-host-spawn-guard.sh; do
  [ -f "$cand" ] && { GUARD_SRC="$cand"; break; }
done

step "per-boot bits: sshd, docker shim, profile.d, host-spawn guard"

SSH_PORT="${DEVBOX_SSH_PORT:-2222}"
# The init_hooks line in dev.ini starts sshd on 2222 at container boot and
# cannot know DEVBOX_SSH_PORT (hooks must stay variable-free), so compare the
# PORT the running daemon was started with — not just "is sshd running".
if [ -x /usr/sbin/sshd ]; then
  # `|| true` is load-bearing: pgrep exits 1 when no sshd runs and `set -o pipefail`
  # would otherwise abort provisioning on a fresh box.
  running_port="$(pgrep -af 'sshd -p [0-9]+' 2>/dev/null | sed -n 's/.*sshd -p \([0-9][0-9]*\).*/\1/p' | head -1 || true)"
  if [ "$running_port" = "$SSH_PORT" ]; then
    say "sshd already listening on :$SSH_PORT"
  else
    if [ -n "$running_port" ]; then
      pkill -x sshd >/dev/null 2>&1 || true
      sleep 1
      say "sshd was on :$running_port, restarting on :$SSH_PORT"
    fi
    install -d -m 755 /run/sshd || true
    ssh-keygen -A >/dev/null 2>&1 || true
    /usr/sbin/sshd -p "$SSH_PORT" >/dev/null 2>&1 || warn "sshd failed to start on port $SSH_PORT"
    say "sshd started on :$SSH_PORT"
  fi
fi

if [ -x /usr/bin/distrobox-host-exec ] && [ ! -L /usr/local/bin/docker ]; then
  ln -sf /usr/bin/distrobox-host-exec /usr/local/bin/docker
  say "docker -> distrobox-host-exec"
fi

if [ ! -f /etc/profile.d/10-nvm.sh ]; then
  cat >/etc/profile.d/10-nvm.sh <<'EOF2'
# nvm (managed by provision-dev.sh / chezmoi)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
EOF2
  chmod 0644 /etc/profile.d/10-nvm.sh
  say "installed /etc/profile.d/10-nvm.sh"
fi

if [ -n "$GUARD_SRC" ]; then
  if ! cmp -s "$GUARD_SRC" /etc/profile.d/00-host-spawn-guard.sh 2>/dev/null; then
    install -m 644 "$GUARD_SRC" /etc/profile.d/00-host-spawn-guard.sh
    say "installed /etc/profile.d/00-host-spawn-guard.sh"
  fi
else
  warn "host-spawn guard not found under $DEV_HOME/.config/distrobox/files"
fi

if [ -f "$MARKER" ] && [ "${DEVBOX_FORCE:-0}" != "1" ]; then
  step "already provisioned for this version (${MARKER})"
  say "DEVBOX_FORCE=1 to run the full provisioning again"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. apt refresh + base tooling
# ---------------------------------------------------------------------------
step "apt: refreshing indexes"
run "apt-get update" apt_get update "$APT_Q"

BASE_PKGS="ca-certificates curl wget gnupg lsb-release apt-transport-https git unzip zip xz-utils procps"
step "apt: base tooling"
say "$BASE_PKGS"
if ! run "apt-get install base packages" apt_get install -y "$APT_Q" --no-install-recommends $BASE_PKGS; then
  for p in $BASE_PKGS; do
    run "apt-get install $p" apt_get install -y "$APT_Q" --no-install-recommends "$p" || warn "skip $p"
  done
fi

if [ "${DEVBOX_SKIP_APT_TOOLING:-0}" != "1" ]; then
  TOOLING_PKGS="bash-completion zsh fzf starship fd-find ripgrep bat eza jq yq tree tmux shellcheck shfmt openssh-server build-essential"
  step "apt: interactive tooling (best-effort)"
  say "$TOOLING_PKGS"
  TOOLING_FAILED=""
  if ! run "apt-get install tooling" apt_get install -y "$APT_Q" --no-install-recommends $TOOLING_PKGS; then
    for p in $TOOLING_PKGS; do
      run "apt-get install $p" apt_get install -y "$APT_Q" --no-install-recommends "$p" \
        || TOOLING_FAILED="$TOOLING_FAILED $p"
    done
  fi

  # starship and eza are not in bookworm main (trixie has both): retry whatever
  # failed from <codename>-backports before falling back to upstream installers.
  if [ -n "${TOOLING_FAILED// /}" ]; then
    if ! grep -rqs "backports" /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null; then
      step "apt: enabling ${SURY_SUITE}-backports"
      cat >/etc/apt/sources.list.d/backports.sources <<EOF2
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${SURY_SUITE}-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF2
      run "apt-get update (backports)" apt_get update "$APT_Q"
    fi
    STILL_FAILED=""
    for p in $TOOLING_FAILED; do
      run "apt-get install -t ${SURY_SUITE}-backports $p" \
        apt_get install -y "$APT_Q" --no-install-recommends -t "${SURY_SUITE}-backports" "$p" \
        || STILL_FAILED="$STILL_FAILED $p"
    done
    TOOLING_FAILED="$STILL_FAILED"
  fi

  if [ "${TOOLING_FAILED// /}" != "" ]; then
    for p in $TOOLING_FAILED; do
      case "$p" in
        starship)
          step "starship: upstream installer -> /usr/local/bin"
          run "starship install.sh" sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin' \
            || warn "starship: installer failed" ;;
        eza)
          # eza is in trixie main only: neither bookworm nor bookworm-backports
          step "eza: upstream release binary -> /usr/local/bin"
          case "$(dpkg --print-architecture)" in
            amd64) EZA_ARCH="x86_64-unknown-linux-gnu" ;;
            arm64) EZA_ARCH="aarch64-unknown-linux-gnu" ;;
            armhf) EZA_ARCH="arm-unknown-linux-gnueabihf" ;;
            *)     EZA_ARCH="" ;;
          esac
          if [ -n "$EZA_ARCH" ]; then
            EZA_TAG="$(curl -fsSL https://api.github.com/repos/eza-community/eza/releases/latest 2>/dev/null \
              | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            : "${EZA_TAG:=v0.23.5}"
            EZA_TMP="$(mktemp -d)"
            if run "download eza ${EZA_TAG}" sh -c \
                 "curl -fsSL 'https://github.com/eza-community/eza/releases/download/${EZA_TAG}/eza_${EZA_ARCH}.tar.gz' -o '$EZA_TMP/eza.tgz' && tar xzf '$EZA_TMP/eza.tgz' -C '$EZA_TMP' ./eza && install -m 755 '$EZA_TMP/eza' /usr/local/bin/eza"; then
              /usr/local/bin/eza --version 2>/dev/null | head -1 || true
            else
              warn "eza: install failed"
            fi
            rm -rf "$EZA_TMP"
          else
            warn "eza: unsupported architecture $(dpkg --print-architecture)"
          fi ;;
        *) warn "not installed: $p" ;;
      esac
    done
  fi
fi

# ---------------------------------------------------------------------------
# 2b. UTF-8 locale
# ---------------------------------------------------------------------------
# distrobox hands the container the host's LANG, but a fresh Debian image has
# only C/C.utf8/POSIX generated until `locales` is installed and locale-gen runs.
# glibc then falls back to ASCII (see `locale charmap`) and zsh starts counting
# the starship prompt in bytes instead of columns — every redraw then erases a
# screen line. Generate the host locale here so the box is UTF-8 natively, and
# make sure C.UTF-8 exists as the fallback 00-env.zsh relies on.
LOC_WANT="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
case "$LOC_WANT" in
  *.[Uu][Tt][Ff]-8|*.[Uu][Tt][Ff]8) ;;
  *) LOC_WANT="C.UTF-8" ;;
esac
LOC_WANT="${LOC_WANT%%@*}"            # strip @euro and friends
LOC_BASE="${LOC_WANT%%.*}"
# `locale -a` spells them de_DE.UTF-8 -> de_DE.utf8
LOC_GREP="$(printf '%s' "$LOC_BASE" | tr 'A-Z' 'a-z').utf8"

step "locale"
# The `locales` package is what provides /etc/locale.gen; a plain debian image has
# only C/C.utf8/POSIX, and C.utf8 being present is NOT proof we can generate the
# host's locale, so test the locale we actually want.
if [ ! -e /etc/locale.gen ] || ! locale -a 2>/dev/null | grep -qx "$LOC_GREP"; then
  run "apt-get install locales" apt_get install -y "$APT_Q" --no-install-recommends locales \
    || warn "locales: install failed"
fi
if [ -e /etc/locale.gen ]; then
  # idempotent: append the two entries we need unless they are already there
  for want in "$LOC_WANT" "C.UTF-8"; do
    grep -qxF "$want" /etc/locale.gen 2>/dev/null || printf '%s\n' "$want" >> /etc/locale.gen
  done
  run "locale-gen" locale-gen || warn "locale-gen failed"
  if command -v update-locale >/dev/null 2>&1; then
    update-locale LANG="$LOC_WANT" >/dev/null 2>&1 || true
  fi
fi
CHARMAP="$(LC_ALL="$LOC_WANT" locale charmap 2>/dev/null || true)"
if [ "$CHARMAP" = "UTF-8" ]; then
  say "locale: $LOC_WANT (UTF-8)"
else
  # C.UTF-8 needs no locale-gen on glibc >= 2.35; if even that is not UTF-8 the
  # image is older than Debian 12 and the prompt cannot be trusted.
  if [ "$(LC_ALL=C.UTF-8 locale charmap 2>/dev/null || true)" = "UTF-8" ]; then
    warn "locale: $LOC_WANT is not UTF-8 (charmap ${CHARMAP:-?}); shells fall back to C.UTF-8"
  else
    warn "locale: no UTF-8 locale available (charmap ${CHARMAP:-?})"
  fi
fi

# ---------------------------------------------------------------------------
# 3. drop the archive's Node (18.x on bookworm) so nothing shadows nvm
# ---------------------------------------------------------------------------
if dpkg -l nodejs 2>/dev/null | grep -q '^ii'; then
  step "apt: purging Debian's nodejs/npm"
  run "apt-get purge nodejs npm" apt_get purge -y "$APT_Q" nodejs npm libnode-dev || true
  run "apt-get autoremove" apt_get autoremove -y "$APT_Q" || true
fi

# ---------------------------------------------------------------------------
# 4. drop the archive's PHP branch so it cannot win /usr/bin/php
# ---------------------------------------------------------------------------
DEB_PHP=""
case "$DEBIAN_MAJOR" in
  12) DEB_PHP="8.2" ;;
  13) DEB_PHP="8.4" ;;
  14) DEB_PHP="8.5" ;;
esac
if ! dpkg -l "php${PHP_BRANCH}-cli" 2>/dev/null | grep -q '^ii'; then
  purge=""
  if [ -n "$DEB_PHP" ] && dpkg -l "php${DEB_PHP}-*" 2>/dev/null | grep -q '^ii'; then
    purge="php${DEB_PHP}-*"
  fi
  dpkg -l 'php-cli' 2>/dev/null | grep -q '^ii' && purge="$purge php-*"
  if [ -n "${purge// /}" ]; then
    step "apt: purging Debian PHP (${DEB_PHP:-metapackages})"
    # shellcheck disable=SC2086
    run "apt-get purge $purge" apt_get purge -y "$APT_Q" $purge || true
    run "apt-get autoremove" apt_get autoremove -y "$APT_Q" || true
  fi
fi

# ---------------------------------------------------------------------------
# 5. nvm + Node (as the container user)
# ---------------------------------------------------------------------------
NVM_TAG="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null \
  | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
: "${NVM_TAG:=v0.40.8}"

if [ ! -s "$DEV_HOME/.nvm/nvm.sh" ]; then
  step "nvm: installing ${NVM_TAG} for ${DEV_USER}"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh" -o /tmp/nvm-install.sh
  chmod 0644 /tmp/nvm-install.sh
  # PROFILE=/dev/null: never append to ~/.zshrc / ~/.bashrc — chezmoi owns those
  # files, so an edit would show up in `chezmoi diff` and be reverted. Sourcing is
  # done by /etc/profile.d/10-nvm.sh (login shells) and the container-only block
  # in ~/.config/zsh/conf.d/00-env.zsh (interactive zsh).
  run "nvm install.sh" as_user "PROFILE=/dev/null bash /tmp/nvm-install.sh --no-use"
  rm -f /tmp/nvm-install.sh
else
  step "nvm: present at ${DEV_HOME}/.nvm"
fi

if [ "$NODE_CHANNEL" = "lts" ] || [ "$NODE_CHANNEL" = "LTS" ]; then
  NVM_INSTALL="nvm install --lts && nvm alias default 'lts/*' && nvm use --lts"
else
  NVM_INSTALL="nvm install '${NODE_CHANNEL}' && nvm alias default '${NODE_CHANNEL}' && nvm use '${NODE_CHANNEL}'"
fi
step "node: ${NODE_CHANNEL}"
run "nvm install ${NODE_CHANNEL}" as_user \
  "export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; ${NVM_INSTALL}"
as_user "export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; printf '    node %s / npm %s\n' \"\$(node -v)\" \"\$(npm -v)\"" || true

step "pnpm / bun"
run "corepack enable / pnpm" as_user "export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; \
  corepack enable >/dev/null 2>&1 || true; \
  corepack prepare pnpm@latest --activate >/dev/null 2>&1 || npm install -g pnpm >/dev/null 2>&1 || true"

if [ ! -x "$DEV_HOME/.bun/bin/bun" ]; then
  run "bun install.sh" as_user "curl -fsSL https://bun.sh/install | bash" || warn "bun install failed (non-fatal)"
fi
if [ -x "$DEV_HOME/.bun/bin/bun" ]; then
  ln -sf "$DEV_HOME/.bun/bin/bun" /usr/local/bin/bun
  chown -h "$DEV_USER:$DEV_GROUP" /usr/local/bin/bun 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 6. PHP from deb.sury.org
# ---------------------------------------------------------------------------
if [ ! -f /usr/share/keyrings/debsuryorg-archive-keyring.gpg ]; then
  step "sury: installing archive keyring"
  run "download keyring .deb" sh -c \
    'curl -fsSL -o /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb'
  run "dpkg -i keyring" dpkg -i /tmp/debsuryorg-archive-keyring.deb
  rm -f /tmp/debsuryorg-archive-keyring.deb
fi

if ! grep -qs "packages.sury.org/php" /etc/apt/sources.list.d/sury-php.sources 2>/dev/null; then
  step "sury: adding repository for ${SURY_SUITE}"
  install -d -m 0755 /etc/apt/sources.list.d
  cat >/etc/apt/sources.list.d/sury-php.sources <<EOF2
Types: deb
URIs: https://packages.sury.org/php/
Suites: ${SURY_SUITE}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/debsuryorg-archive-keyring.gpg
EOF2
  run "apt-get update (sury)" apt_get update "$APT_Q"
fi

if ! dpkg -l "php${PHP_BRANCH}-cli" 2>/dev/null | grep -q '^ii'; then
  step "php: installing ${PHP_BRANCH} from Sury"
  # Resolve extension -> phpX.Y-<ext> against what the repo actually publishes.
  # Not every extension exists as a package for every branch: since PHP 8.5
  # OPcache is built into the binary and there is no php8.5-opcache at all, and
  # a single unknown name aborts the whole apt-get run.
  PHP_PKGS=""; PHP_SKIP=""
  for ext in cli fpm opcache curl mbstring xml zip gd intl bcmath sqlite3 mysql pgsql redis; do
    cand="php${PHP_BRANCH}-${ext}"
    if apt-cache show "$cand" >/dev/null 2>&1; then
      PHP_PKGS="$PHP_PKGS $cand"
    else
      PHP_SKIP="$PHP_SKIP $ext"
    fi
  done
  say "modules:$(printf '%s' "$PHP_PKGS" | sed "s/ php${PHP_BRANCH}-/ /g")"
  [ -n "$PHP_SKIP" ] && note "not packaged for php${PHP_BRANCH} (skipped):${PHP_SKIP}"
  # shellcheck disable=SC2086  # word splitting is the point here
  run "apt-get install php${PHP_BRANCH}" apt_get install -y "$APT_Q" --no-install-recommends $PHP_PKGS
else
  step "php: ${PHP_BRANCH} already installed"
fi

if [ -x "/usr/bin/php${PHP_BRANCH}" ] && ! "/usr/bin/php${PHP_BRANCH}" -m 2>/dev/null | grep -qi opcache; then
  warn "php${PHP_BRANCH} -m does not list OPcache — expected: built in since 8.5, package before that"
fi

if [ -x "/usr/bin/php${PHP_BRANCH}" ]; then
  update-alternatives --install /usr/bin/php php "/usr/bin/php${PHP_BRANCH}" 85 >/dev/null 2>&1 || true
  update-alternatives --set php "/usr/bin/php${PHP_BRANCH}" >/dev/null 2>&1 || true
fi

if ! command -v composer >/dev/null 2>&1; then
  step "composer: installing /usr/local/bin/composer"
  EXPECTED="$(curl -fsSL https://composer.github.io/installer.sig 2>/dev/null || true)"
  run "download composer installer" sh -c 'curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php'
  if [ -n "$EXPECTED" ] && [ "$EXPECTED" = "$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")" ]; then
    run "php composer-setup.php" php /tmp/composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
  else
    warn "composer installer signature mismatch — skipping"
  fi
  rm -f /tmp/composer-setup.php
fi

# ---------------------------------------------------------------------------
# 7. oh-my-zsh + plugins, owned by the user (never /root)
# ---------------------------------------------------------------------------
if [ ! -d "$DEV_HOME/.oh-my-zsh" ]; then
  step "zsh: installing oh-my-zsh for ${DEV_USER}"
  run "oh-my-zsh install.sh" as_user \
    "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"" \
    || warn "oh-my-zsh install failed (non-fatal)"
fi

if [ -d "$DEV_HOME/.oh-my-zsh" ]; then
  step "zsh: plugins"
  for repo in \
    zsh-users/zsh-autosuggestions \
    zsh-users/zsh-syntax-highlighting \
    zsh-users/zsh-history-substring-search \
    Aloxaf/fzf-tab
  do
    name="${repo#*/}"
    dest="$DEV_HOME/.oh-my-zsh/custom/plugins/$name"
    if [ ! -d "$dest/.git" ]; then
      run "clone $name" as_user "git clone --depth=1 https://github.com/${repo}.git '$dest'" \
        || warn "clone failed: $repo"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 8. marker + report
# ---------------------------------------------------------------------------
touch "$MARKER"

step "versions"
{
  as_user "export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; \
    printf '    %-9s %s\n' node \"\$(node -v 2>/dev/null || echo MISSING)\"; \
    printf '    %-9s %s\n' npm \"\$(npm -v 2>/dev/null || echo MISSING)\""
  printf '    %-9s %s\n' php "$(php -v 2>/dev/null | head -1)"
  printf '    %-9s %s\n' composer "$(composer --version 2>/dev/null | head -1)"
  printf '    %-9s %s\n' debian "$(cat /etc/debian_version)"
} || true

step "done (marker ${MARKER})"
say "re-enter the box so nvm is on PATH"

summary
