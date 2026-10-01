# git-wt

An interactive `git worktree list` picker using `fzf`.

- **Enter** changes the current shell directory to the selected worktree.
- **x** asks for confirmation, then runs `git worktree remove` for the selected
  worktree. Git refuses to remove a dirty worktree. The branch is retained.
- **Esc** leaves the directory and worktrees alone.

Requires Git, fzf, Python 3.9 or newer, and zsh, bash, or fish.

Run `./setup.sh` from the shell you want to use. It installs the `git-wt`
executable under `~/.local/bin` and enables the function for that shell only.
For zsh or bash it adds a source line to the shell's rc file; for fish it links
a file into `~/.config/fish/conf.d`. To select a shell explicitly, run
`./setup.sh --shell fish` (or `zsh` or `bash`). Rerun setup after moving the
repository. Open a new shell, then run `git wt` inside a Git worktree.

The shell function handles `git wt` and passes other `git` commands through.
The standalone `git-wt` executable prints a selected path; it cannot change
its parent shell's directory on its own.
