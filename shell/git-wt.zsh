# Source this file from an interactive zsh shell.
function git() {
    if [[ "$1" == "wt" ]]; then
        local destination
        destination=$(command git wt "${@:2}") || return $?
        if [[ -n "$destination" ]]; then
            cd -- "$destination" || return $?
        fi
        return 0
    fi
    command git "$@"
}
