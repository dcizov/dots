#!/usr/bin/env bash
# Grant open-remote-ssh its API proposals WITHOUT taking ownership of
# ~/.vscode-oss/argv.json.
#
# VSCodium creates that file at first launch and writes a per-install
# "crash-reporter-id" into it; the stock template also carries
# "enable-crash-reporter": false. A chezmoi-MANAGED copy would replace the
# whole file on every apply, dropping both plus the header comments. So this
# run script PATCHES the file in place instead and never owns it.
#
# Why the proposals matter: open-remote-ssh contributes its "SSH Targets"
# view (id sshHosts) into the built-in Remote container, gated behind the
# contribViewsRemote proposal. Without it, createTreeView('sshHosts') in
# src/extension.ts:23 throws "No view is registered with id: sshHosts" and
# activation aborts right after the resolver is registered.
#
# Idempotent, and a no-op on machines without VSCodium.
# NOTE: VSCodium only reads argv.json at startup -- restart it afterwards.
set -euo pipefail

ARGV="$HOME/.vscode-oss/argv.json"

[ -f "$ARGV" ] || exit 0
if grep -q '"enable-proposed-api"' "$ARGV"; then
	exit 0
fi

# Insert one member before the closing brace at column 0, leaving comments,
# indentation and every existing key untouched. The leading comma on the new
# line is valid JSON and avoids touching the previous line.
sed -i 's|^}$|\t,"enable-proposed-api": ["jeanp413.open-remote-ssh"]\n}|' "$ARGV"

echo "argv.json: granted proposals to jeanp413.open-remote-ssh (restart VSCodium)"
