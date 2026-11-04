# Dev box

The `dev` box is a rootless distrobox on **Debian 13 (trixie)**, defined
entirely in this repo:

| file | role |
|---|---|
| `private_dot_config/distrobox/dev.ini` | manifest: image, packages, init hook |
| `private_dot_config/distrobox/executable_provision-dev.sh` | provisioning (nvm + Node LTS, PHP 8.5 from Sury, composer, oh-my-zsh, sshd) |
| `private_dot_config/distrobox/devbox.env` | per-machine tunables (`NODE_CHANNEL`, `PHP_BRANCH`, `DEVBOX_SSH_PORT`) |
| `private_dot_local/share/ucli/scripts/devbox/executable_devbox-reconcile.sh` | create-or-update, the single entry point |

```bash
ucli devbox              # enter the box (reconciles first if dev.ini exists)
ucli devbox-reconcile    # create the box, or bring it in line with this commit
ucli devbox-recreate     # rebuild it (Debian bump, image/volume/init_hooks change)
```

Everything else is a hidden recipe: it still runs when you name it, but it stays
out of `ucli --list` and out of both menus (the gum list and `ucli --choose`
only ever show public recipes), so the dev-box group stays three lines:

```bash
ucli --show devbox-versions     # also: --show devbox-log, devbox-vscode-doctor
ucli devbox-versions            # versions inside the box
```

The menus use `gum` when it is installed (the same TUI ujust uses) and fall back
to a plain numbered list — `ui.sh` picks whichever is there. `gum` is part of the
`UCLI_RUNTIME` tier, so `ucli setup-system` and `sudo ucli setup-desktop` bring it
in; `fzf` comes with `ucli cli` and is what `ucli --choose` uses.

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
