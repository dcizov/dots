# Fish completion for ucli — the same trick as the zsh one: recipe names come from
# the justfile itself (`just --summary`), so a new recipe completes as soon as it
# is deployed. ujust ships alias-only fish support; this is the completion itself.

function __ucli_justfile
    if set -q UCLI_JUSTFILE
        echo $UCLI_JUSTFILE
    else
        echo $HOME/.config/ucli/justfile
    end
end

function __ucli_recipes
    set -l jf (__ucli_justfile)
    test -r $jf; or return
    command -q just; or return
    just --summary --justfile $jf 2>/dev/null | string split ' '
end

complete -c ucli -f
complete -c ucli -n '__fish_use_subcommand' -a '(__ucli_recipes)' -d 'ucli recipe'
