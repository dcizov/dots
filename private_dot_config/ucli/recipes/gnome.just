# GNOME menu. Use `ucli --choose` to pick a GNOME recipe interactively.
[group('GNOME')]
gnome:
    # apply managed GNOME dconf settings profile
    @~/.local/share/ucli/scripts/install/executable_apply-gnome-settings.sh

# Apply managed GNOME dconf settings profile.
_apply-settings:
    @~/.local/share/ucli/scripts/install/executable_apply-gnome-settings.sh

# Analyze GNOME package/extension state.
_analyze:
    @~/.local/share/ucli/scripts/gnome/executable_gnome-analyze.sh

# Backup GNOME settings.
_settings-backup:
    @~/.local/share/ucli/scripts/gnome/executable_gnome-settings.sh backup

# Restore GNOME Shell settings.
_restore-shell dir:
    @~/.local/share/ucli/scripts/gnome/executable_gnome-settings.sh restore-shell "{{dir}}"

# Restore GNOME extension settings.
_restore-extensions dir:
    @~/.local/share/ucli/scripts/gnome/executable_gnome-settings.sh restore-extensions "{{dir}}"

# Restore GNOME desktop settings.
_restore-desktop dir:
    @~/.local/share/ucli/scripts/gnome/executable_gnome-settings.sh restore-desktop "{{dir}}"

# Install Better Tray Icons.
_better-tray-icons:
    @~/.local/share/ucli/scripts/gnome/executable_install-better-tray-icons.sh --update --enable

# Install ChromaLeon.
_chromaleon:
    @~/.local/share/ucli/scripts/gnome/executable_install-gnome-extension.sh --pk 10070 --enable --force

# Install user-managed GNOME extensions.
_user-extensions:
    @~/.local/share/ucli/scripts/gnome/executable_install-gnome-user-extensions.sh
