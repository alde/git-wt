#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
share_dir="$HOME/.local/share/git-wt"
bin_dir="$HOME/.local/bin"
fish_dir="$HOME/.config/fish/conf.d"

if [[ $# -eq 0 ]]; then
    parent_shell=$(ps -p "$PPID" -o comm=) || {
        printf 'Cannot detect the current shell; use --shell zsh|bash|fish\n' >&2
        exit 1
    }
    shell_name=${parent_shell##*/}
    shell_name=${shell_name#-}
elif [[ $# -eq 2 && "$1" == --shell ]]; then
    shell_name=$2
else
    printf 'usage: ./setup.sh [--shell zsh|bash|fish]\n' >&2
    exit 2
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

install_source_line() {
    local config=$1 shell=$2
    local line=". \"\$HOME/.local/share/git-wt/shell/git-wt.$shell\""
    touch "$config"
    if ! grep -Fqx "$line" "$config"; then
        printf '\n# git-wt shell integration\n%s\n' "$line" >> "$config"
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

printf 'Installed git-wt for %s. Open a new shell, then run git wt.\n' "$shell_name"
