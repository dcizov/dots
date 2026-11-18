# Generate a private manifest; --exclude-path PATH prunes the AppImage scan.
[group('Inventory')]
[positional-arguments]
inventory *ARGS:
    @exec "$HOME/.local/share/ucli/scripts/inventory/inventory.sh" "$@"

# Manual Restic home backup; preflight shows sources and exact path exclusions.
[group('Inventory')]
[positional-arguments]
backup *ARGS:
    @exec "$HOME/.local/share/ucli/scripts/backup/backup-home.sh" "$@"
