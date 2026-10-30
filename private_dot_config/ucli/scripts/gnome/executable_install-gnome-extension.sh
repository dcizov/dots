#!/usr/bin/env bash
set -euo pipefail
usage(){ echo 'usage: install-gnome-extension.sh (--uuid UUID | --pk ID) [--enable] [--force]'; }
uuid=""; pk=""; enable=0; force=0
while (($#)); do case "$1" in --uuid) uuid="${2:-}"; shift 2;; --uuid=*) uuid="${1#*=}"; shift;; --pk) pk="${2:-}"; shift 2;; --pk=*) pk="${1#*=}"; shift;; --enable) enable=1; shift;; --force) force=1; shift;; -h|--help) usage; exit 0;; *) echo "unknown arg: $1" >&2; usage; exit 2;; esac; done
[[ -n "$uuid" || -n "$pk" ]] || { usage >&2; exit 2; }
for cmd in curl gnome-shell gnome-extensions python3; do command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd" >&2; exit 1; }; done
shell_version="$(gnome-shell --version | awk '{print $NF}')"
query="shell_version=${shell_version}"
[[ -n "$uuid" ]] && query="uuid=${uuid}&${query}" || query="pk=${pk}&${query}"
info_json="$(curl -fsSL "https://extensions.gnome.org/extension-info/?${query}")"
download_path="$(python3 -c 'import json,sys; info=json.load(sys.stdin); print(info.get("download_url", ""))' <<<"$info_json")"
resolved_uuid="$(python3 -c 'import json,sys; info=json.load(sys.stdin); print(info.get("uuid", ""))' <<<"$info_json")"
[[ -n "$download_path" ]] || { echo "download_url missing in extension-info response" >&2; exit 1; }
zip_path="$(mktemp --suffix=.zip)"; trap 'rm -f "$zip_path"' EXIT
curl -fL "https://extensions.gnome.org${download_path}" -o "$zip_path"
args=(install "$zip_path"); ((force)) && args+=(--force)
gnome-extensions "${args[@]}"
if ((enable)) && [[ -n "$resolved_uuid" ]]; then gnome-extensions enable "$resolved_uuid" || echo "Installed but enabling failed; log out/in then enable $resolved_uuid" >&2; fi
echo "Installed GNOME extension: ${resolved_uuid:-$uuid$pk}"
