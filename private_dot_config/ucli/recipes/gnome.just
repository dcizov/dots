# GNOME menu. Use `ucli --choose` to pick a GNOME recipe interactively.
[group('GNOME')]
gnome:
    # apply managed GNOME dconf settings profile
    @~/.local/share/ucli/scripts/install/apply-gnome-settings.sh

# Apply managed GNOME dconf settings profile.
_apply-settings:
    @~/.local/share/ucli/scripts/install/apply-gnome-settings.sh

# Analyze GNOME package/extension state.
_analyze:
    @~/.local/share/ucli/scripts/gnome/gnome-analyze.sh

# Backup GNOME settings.
_settings-backup:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh backup

# Restore GNOME Shell settings.
_restore-shell dir:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh restore-shell "{{dir}}"

# Restore GNOME extension settings.
_restore-extensions dir:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh restore-extensions "{{dir}}"

# Restore GNOME desktop settings.
_restore-desktop dir:
    @~/.local/share/ucli/scripts/gnome/gnome-settings.sh restore-desktop "{{dir}}"

# Install user-managed GNOME extensions via gnome-extensions-cli (gext).
# Installs personal extensions (BetterTrayIcons, user-accent-colors,
# just-perfection, copyous, gnome-ui-tune, logomenu, etc.)
_user-extensions:
    @~/.local/share/ucli/scripts/install/install-gnome-user-extensions.sh
