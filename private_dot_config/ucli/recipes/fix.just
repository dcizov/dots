# Repair the machine in place. Every action is idempotent, says what it will do
# before doing it, and refuses the case where "repair" would make things worse
# (fix lock will not remove a lock a running pacman holds).
#
#   ucli fix                 list the actions
#   ucli fix keyrings        refresh pacman's keys (--reset re-initialises)
#   ucli fix lock            remove a stale /var/lib/pacman/db.lck
#   ucli fix orphans         remove packages nothing requires any more
#   ucli fix cache           keep the 2 newest versions + vacuum the journal
#   ucli fix native          reinstall every repository package in place
#
# `--dry-run` works on all of them; `--yes` skips the questions (keyrings,
# orphans, cache, native); native wants the word "reinstall" typed instead.
#
# These are the "Fix" buttons CachyOS Hello puts in a window. What is here maps
# 1:1 to the ones that apply to an Arch install; rpm-ostree/akmods/winboat do not.
[group('Fix')]
fix *ARGS:
    # keyrings | lock | orphans | cache | native   (every action takes --dry-run)
    @~/.local/share/ucli/scripts/fix/fix.sh {{ARGS}}
