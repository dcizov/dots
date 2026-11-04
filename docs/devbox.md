# Dev box

The `dev` box is a rootless distrobox on **Debian 13 (trixie)**, defined
entirely in this repo:

| file | role |
|---|---|
| `private_dot_config/distrobox/dev.ini` | manifest: image, packages, init hook |
| `private_dot_config/distrobox/executable_provision-dev.sh` | provisioning (nvm + Node LTS, PHP 8.5 from Sury, composer, oh-my-zsh, sshd) |
| `private_dot_config/distrobox/devbox.env` | per-machine tunables (`NODE_CHANNEL`, `PHP_BRANCH`, `DEVBOX_SSH_PORT`) |
| `private_dot_config/ucli/scripts/devbox/executable_devbox-reconcile.sh` | create-or-update, the single entry point |

```bash
ucli devbox              # menu: reconcile, shell, versions, log, reprovision,
                         #       recreate, dry-run, vscode-doctor, vscode-bisect
ucli devbox-reconcile    # create the box, or bring it in line with this commit
ucli devbox-shell        # distrobox enter dev
```

The rarely-typed actions are hidden recipes (`_devbox-versions`, `_devbox-recreate`,
`_devbox-log`, …) so the list stays readable — they still run if you name them,
and the menu is the discoverable path:

```bash
ucli --show _devbox-recreate    # what the menu entry runs
ucli _devbox-versions           # direct
```

The menus use `gum` when it is installed (the TUI ujust uses), then `fzf`, then
a plain numbered list — `UCLI_MENU=gum|fzf|select` forces one. `gum` is part of
the `UCLI_RUNTIME` tier, so `ucli setup-system` and `sudo ucli setup-desktop`
bring it in; `fzf` comes with `ucli cli`.

`distrobox assemble create` on its own only creates a bare container — no Node,
no PHP, nothing provisioned. Always go through `ucli devbox-reconcile`
(or `ucli devmode`, which calls it).

After a full run: `debian 13.x`, `node v26.x`, `php 8.5.x`, `composer 2.x`,
sshd on `$DEVBOX_SSH_PORT` (default 2222).

### Throwaway boxes

`dev` is the box that gets provisioned. For anything else there is
`ucli devbox-create`:

```bash
ucli devbox-create --list           # ubuntu fedora wolfi debian arch alpine
ucli devbox-create ubuntu           # container named "ubuntu"
ucli devbox-create fedora scratch   # custom name
```

That is `distrobox create --image <stock image> --yes` with a checked image
list — the Bluefin "preconfigured Ubuntu/Fedora/Wolfi boxes" idea without a
second provisioning path. No node/php, no sshd, no reconcile: delete it with
`distrobox rm -f <name>` when you are done.

Dev databases run on the host, not in the box:

```bash
cd ~/.config/dev-services
docker compose up -d
docker compose ps
docker compose down
```

Published on loopback only (`127.0.0.1:5432`, `:3306`, `:6379`), which is
reachable from inside the box because distrobox shares the host network
namespace. Keep app connection strings on `127.0.0.1`, not `localhost`
(`localhost` resolves to `::1` first and the port mapping is IPv4).
