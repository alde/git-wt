# Loaded automatically from ~/.config/fish/conf.d.
function git
    if test "$argv[1]" = wt
        set -l destination (command git wt $argv[2..-1]); or return $status
        if test -n "$destination"
            cd -- "$destination"; or return $status
        end
        return 0
    end
    command git $argv
end
