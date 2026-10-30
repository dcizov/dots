# GNOME menu.
[group('GNOME')]
gnome:
    #!/usr/bin/env bash
    set -euo pipefail
    items=(
      'extensions|Install/enable default GNOME extensions'
      'apply-settings|Apply managed GNOME dconf settings profile'
      'analyze|Analyze GNOME package/extension state'
      'settings-backup|Backup GNOME settings'
      'restore-shell|Restore GNOME Shell settings from dir'
      'restore-extensions|Restore GNOME extension settings from dir'
      'restore-desktop|Restore GNOME desktop settings from dir'
      'better-tray-icons|Install Better Tray Icons'
      'chromaleon|Install ChromaLeon'
      'user-extensions|Install user-managed GNOME extensions'
    )
    if command -v fzf >/dev/null 2>&1; then
      choice="$(printf '%s\n' "${items[@]}" | fzf --prompt='gnome> ' --with-nth=1,2 --delimiter='|')" || exit 0
      choice="${choice%%|*}"
    else
      select item in "${items[@]}"; do choice="${item%%|*}"; break; done
    fi
    case "$choice" in
      extensions) ~/.config/ucli/scripts/install/install-gnome-extension-set.sh system ;;
      apply-settings) ~/.config/ucli/scripts/install/apply-gnome-settings.sh ;;
      analyze) ~/.config/ucli/scripts/gnome/gnome-analyze.sh ;;
      settings-backup) ~/.config/ucli/scripts/gnome/gnome-settings.sh backup ;;
      restore-shell)
        read -r -p 'settings backup dir: ' dir
        ~/.config/ucli/scripts/gnome/gnome-settings.sh restore-shell "$dir"
        ;;
      restore-extensions)
        read -r -p 'settings backup dir: ' dir
        ~/.config/ucli/scripts/gnome/gnome-settings.sh restore-extensions "$dir"
        ;;
      restore-desktop)
        read -r -p 'settings backup dir: ' dir
        ~/.config/ucli/scripts/gnome/gnome-settings.sh restore-desktop "$dir"
        ;;
      better-tray-icons) ~/.config/ucli/scripts/gnome/install-better-tray-icons.sh --update --enable ;;
      chromaleon) ~/.config/ucli/scripts/gnome/install-gnome-extension.sh --pk 10070 --enable --force ;;
      user-extensions) ~/.config/ucli/scripts/gnome/install-gnome-user-extensions.sh ;;
    esac

# Apply managed GNOME dconf settings profile.
_apply-settings:
    ~/.config/ucli/scripts/install/apply-gnome-settings.sh

# Analyze GNOME package/extension state.
_analyze:
    ~/.config/ucli/scripts/gnome/gnome-analyze.sh

# Backup GNOME settings.
_settings-backup:
    ~/.config/ucli/scripts/gnome/gnome-settings.sh backup

# Restore GNOME Shell settings.
_restore-shell dir:
    ~/.config/ucli/scripts/gnome/gnome-settings.sh restore-shell "{{dir}}"

# Restore GNOME extension settings.
_restore-extensions dir:
    ~/.config/ucli/scripts/gnome/gnome-settings.sh restore-extensions "{{dir}}"

# Restore GNOME desktop settings.
_restore-desktop dir:
    ~/.config/ucli/scripts/gnome/gnome-settings.sh restore-desktop "{{dir}}"

# Install Better Tray Icons.
_better-tray-icons:
    ~/.config/ucli/scripts/gnome/install-better-tray-icons.sh --update --enable

# Install ChromaLeon.
_chromaleon:
    ~/.config/ucli/scripts/gnome/install-gnome-extension.sh --pk 10070 --enable --force

# Install user-managed GNOME extensions.
_user-extensions:
    ~/.config/ucli/scripts/gnome/install-gnome-user-extensions.sh
