# Generate a private package/app/settings manifest (not a file backup).
[group('Inventory')]
[positional-arguments]
inventory *ARGS:
    @exec "$HOME/.local/share/ucli/scripts/inventory/inventory.sh" "$@"

# Verify or run a manual Restic home backup; start with preflight.
[group('Inventory')]
[positional-arguments]
backup *ARGS:
    @exec "$HOME/.local/share/ucli/scripts/backup/backup-home.sh" "$@"
