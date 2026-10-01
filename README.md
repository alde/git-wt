# git-wt

An interactive `git worktree list` picker using `fzf`.

- **Tab** marks or unmarks worktrees for removal.
- **Enter** changes the current shell directory to a single selected worktree.
- **x** asks for one confirmation, then runs `git worktree remove` for each
  marked worktree (or the focused worktree if none are marked). Git refuses to
  remove a dirty worktree; removal continues for the others. The current
  worktree is skipped. Branches are retained.
- **Ctrl-S** checks whether the focused worktree has local changes.
- **Esc** leaves the directory and worktrees alone.

The preview shows how many commits the focused worktree's HEAD is ahead of and
behind the local `main` branch (or `master` if there is no `main`), and whether
that HEAD is contained in the base branch. The counts use local refs and do
not fetch. A squash merge will not appear as contained. The full dirty check,
including untracked files, runs only when you press Ctrl-S; it can take several
seconds in a large worktree.

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
