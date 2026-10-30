# 00-host-spawn-guard.sh -- keep stdin intact for non-interactive login shells.
#
# (unchanged in this exercise -- for brevity the long explanation comment is
#  omitted in the sandbox replica; use your existing file verbatim.)
case $- in
        *i*) ;;
        *)
                case ${BASH_VERSION:-}${ZSH_VERSION:-} in
                        '') ;;
                        *) eval 'host-spawn() { :; }' ;;
                esac
                ;;
esac
