# How this compares to Bluefin

Bluefin's recipe (`system_files/bluefin/usr/share/ublue-os/just/system.just`)
is a **toggle**, not an installer: it runs `ublue-bling`, which adds or removes a
single `source /usr/share/ublue-os/bling/bling.sh` line in `~/.zshrc`
(`.bashrc`/fish `config.fish` for other shells). Only when turning the feature
*on* does it also run `brew bundle --file=/usr/share/ublue-os/homebrew/cli.Brewfile`,
which pulls `bat chezmoi direnv dysk eza fd gh podman-tui ripgrep tealdeer
trash-cli yq zoxide starship mise`. Turning it off just removes the source line —
the packages stay, you get your old shell back.

The snippet it sources is a flag-gated alias layer, all defaulting to on:
`BLUEFIN_SHELL_ENABLE_{EZA,UGREP,BAT,ATUIN,STARSHIP,ZOXIDE,UUTILSCOREUTILS,
UUTILSFINDUTILS,UUTILSDIFFUTILS,MOTD}` (`CARAPACE` off). Concretely: `eza` for
`ls/ll/l./l1`, `bat` for `cat`, `ug` for `grep/egrep/fgrep`, the uutils
coreutils/findutils/diffutils Rust binaries prepended to `PATH`, `atuin init`,
`starship init`, `zoxide init`, and a MOTD on new shells. It ships no shell
framework and no plugins — it decorates whatever shell you already run. The
cross-platform `bluefin-cli` binary (mac/WSL) is the same idea:
`brew install ublue-os/experimental-tap/bluefin-cli`, then
`bluefin-cli shell zsh on`.

ucli's equivalent is split differently on purpose: `install-shell.sh` owns the
framework (zsh + oh-my-zsh + plugin clones + `chsh`), `SHELL_TOOLS` brings
starship, `ucli cli` adds the cosmetic binaries, and the alias/init layer lives
in `~/.config/zsh/conf.d/*` under chezmoi — so it is versioned, diffable, and
`ucli chezmoi-apply` is the "toggle" (edit the file, re-apply).

## What this repo took, and what it left

| Bluefin feature | Here |
|---|---|
| flagged alias layer (`BLUEFIN_SHELL_ENABLE_*`) | yes — `UCLI_SHELL_ENABLE_*` in `conf.d/`, overrides in `~/.config/zsh/local.zsh` |
| `ugrep` | yes, as its own `ug` command in `DEV_CLI` |
| login MOTD (`uwelcome`, `bluefin-cli motd show`) | yes, login-shells-only `fastfetch`, toggle with `ucli motd on\|always\|off` |
| `fastfetch` aliased as `neofetch` | no need — `neofetch` is archived (April 2024); `fastfetch` is already in `SYSTEM_QOL_TOOLS` |
| uutils coreutils/findutils/diffutils on `PATH` | **no** — flag differences and host/box drift for a gain `eza`/`fd`/`rg` already give interactively |
| `carapace` completions | **no** — it competes with oh-my-zsh's `compinit` and `fzf-tab`; upstream ships it off by default too |
| `grep` aliased to `ug` | **no** — see above |

The one structural difference: Bluefin's toggle is a `source` line in `~/.zshrc`
plus a Brewfile run; here the whole layer is chezmoi-managed files, so `chezmoi
diff` is the "what changed" view and `ucli chezmoi-apply` is the toggle.
