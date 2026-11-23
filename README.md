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
repository. Setup installs from whichever checkout runs it, so running it in a
worktree lets you try a branch; rerun it from the main checkout to go back.
Open a new shell, then run `git wt` inside a Git worktree.

## Rex

If you use [Rex](https://www.superlogical.com/rex/), run `./setup.sh --rex`
as well. It adds **Git: Open Worktree…** to the Rex command palette, which
lists the worktrees of every repository under `~/src`, with the main checkout
first in each repository. If [zoxide](https://github.com/ajeetdsouza/zoxide)
is installed, the repositories you visit most come first, and picking one
counts as a visit; without it they are alphabetical. Each repository gets one
Rex session, named after it, with a tab per worktree named after the branch.
Picking a worktree switches to its tab, creating the session or the tab with a
shell in the worktree if needed. A repository is named by the shortest trailing
part of its path that no other repository shares, such as `alde/tool` when two
checkouts are called `tool`, so their sessions stay apart. To bind a key, add
a line such as `rex.bind("shift+cmd+k", "git_wt_open")` to `init.lua`.

**Git: Clean Up Stale Worktrees…** opens a pane below the focused one running
`git wt --clean-all` (see [Cleaning up](#cleaning-up)). While it runs it
reports its progress to Rex over the program status protocol (OSC 7501), so the
tab shows when it is waiting on you. The pane closes when it finishes, and the
result arrives as a desktop notification, which Rex shows if notifications are
enabled in its settings. Tabs for removed worktrees are left open. Setting
`GIT_WT_NOTIFY=1` gives the same notification outside Rex.

Setup links `rex/git-wt.lua` into the Rex configuration directory and adds
`require("git-wt")` to `init.lua`. Without `--rex`, nothing touches Rex, and
`git wt` works the same either way. `./setup.sh --remove-rex` undoes both and
leaves the rest of git-wt installed.

Repositories are found by scanning up to four levels below each root, without
descending into checkouts. Set `GIT_WT_ROOTS` to a colon-separated list of
directories to scan elsewhere; for the Rex picker it must be set in the Rex
server's environment. `git-wt --list-all` and `git-wt --list-stale` print
the lists as JSON.

## Cleaning up

`git wt --clean` offers the stale worktrees of the current repository for
removal; `git wt --clean-all` does the same for every repository under
`GIT_WT_ROOTS`. A linked worktree is stale when its HEAD is already in the
local base branch, or its branch's upstream is gone, which is how a
squash-merged branch usually looks after `git fetch --prune`. Nothing is
fetched. Worktrees with uncommitted changes are listed as kept and not offered.
Every stale worktree starts marked: Tab unmarks, Enter removes the marked ones
after one confirmation, and Esc cancels. Branches are kept. A new worktree with
no commits yet also counts as merged, so unmark any you are still using.

## Notes

The shell function handles `git wt` and passes other `git` commands through.
The standalone `git-wt` executable prints a selected path; it cannot change
its parent shell's directory on its own.
