#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
share_dir="$HOME/.local/share/git-wt"
bin_dir="$HOME/.local/bin"
fish_dir="$HOME/.config/fish/conf.d"
rex_dir="${XDG_CONFIG_HOME:-$HOME/.config}/rex"
usage='usage: ./setup.sh [--shell zsh|bash|fish] [--rex]'

shell_name=
with_rex=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --shell)
            [[ $# -ge 2 ]] || { printf '%s\n' "$usage" >&2; exit 2; }
            shell_name=$2
            shift 2
            ;;
        --rex)
            with_rex=true
            shift
            ;;
        *)
            printf '%s\n' "$usage" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$shell_name" ]]; then
    parent_shell=$(ps -p "$PPID" -o comm=) || {
        printf 'Cannot detect the current shell; use --shell zsh|bash|fish\n' >&2
        exit 1
    }
    shell_name=${parent_shell##*/}
    shell_name=${shell_name#-}
fi

case "$shell_name" in
    zsh|bash|fish) ;;
    *)
        printf 'Unsupported shell: %s (use --shell zsh|bash|fish)\n' "$shell_name" >&2
        exit 2
        ;;
esac

for tool in git python3 fzf; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'git-wt needs %s on PATH\n' "$tool" >&2
        exit 1
    fi
done

install_link() {
    local target=$1 destination=$2
    if [[ -e "$destination" && ! -L "$destination" ]]; then
        printf 'Refusing to replace %s\n' "$destination" >&2
        return 1
    fi
    ln -sfn "$target" "$destination"
}

append_line_once() {
    local config=$1 comment=$2 line=$3
    touch "$config"
    if ! grep -Fqx "$line" "$config"; then
        printf '\n%s\n%s\n' "$comment" "$line" >> "$config"
    fi
}

install_source_line() {
    local config=$1 shell=$2
    append_line_once "$config" '# git-wt shell integration' \
        ". \"\$HOME/.local/share/git-wt/shell/git-wt.$shell\""
}

install_rex() {
    mkdir -p "$rex_dir"
    install_link "$share_dir/rex/git-wt.lua" "$rex_dir/git-wt.lua"
    append_line_once "$rex_dir/init.lua" '-- git-wt worktree picker' 'require("git-wt")'
    if command -v rex >/dev/null 2>&1; then
        rex config reload >/dev/null || printf 'Run rex config reload to load the picker\n' >&2
    fi
}

mkdir -p "$bin_dir" "$(dirname "$share_dir")"
install_link "$repo_dir" "$share_dir"
install_link "$share_dir/git-wt" "$bin_dir/git-wt"
if [[ "$shell_name" == fish ]]; then
    mkdir -p "$fish_dir"
    install_link "$share_dir/shell/git-wt.fish" "$fish_dir/git-wt.fish"
else
    install_source_line "$HOME/.$shell_name"rc "$shell_name"
fi

if [[ "$with_rex" == true ]]; then
    install_rex
    printf 'Added "Git: Open Worktree…" to the Rex command palette.\n'
fi

printf 'Installed git-wt for %s. Open a new shell, then run git wt.\n' "$shell_name"
