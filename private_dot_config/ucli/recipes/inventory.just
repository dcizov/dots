# Generate package/app/settings inventory.
[group('Inventory')]
inventory:
    # list installed packages, apps, and settings
    @~/.config/ucli/scripts/inventory/executable_inventory.sh
