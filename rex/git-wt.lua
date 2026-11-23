-- Rex integration for git-wt. Installed by `./setup.sh --rex`.
--
-- Git: Open Worktree… picks a worktree from any repository under
-- GIT_WT_ROOTS and switches to its tab in the repository's session,
-- creating the session or the tab, with a shell in the worktree, if missing.
--
-- Git: Clean Up Stale Worktrees… opens a pane running `git-wt --clean-all`,
-- which offers the worktrees whose work is merged or whose upstream branch
-- is gone and removes the ones left marked.

local HOME = os.getenv("HOME")
local GIT_WT = HOME .. "/.local/bin/git-wt"
-- Listing ~100 repositories takes under a second; the margin covers a cold
-- disk cache while staying inside an action's 30-second limit.
local LIST_TIMEOUT_SECONDS = 20
local SHELL = "com.superlogical.terminal.shell"

local function git_wt(flag)
  local result, err = rex.exec({ GIT_WT, flag }, { timeout = LIST_TIMEOUT_SECONDS })
  if result == nil then
    error("git-wt: " .. err)
  end
  if not result.ok then
    error("git-wt " .. flag .. " failed: " .. result.stderr)
  end
  return assert(rex.json.decode(result.stdout))
end

local function picker_title(worktree)
  return worktree.repo .. ":" .. worktree.branch
end

local function shorten_home(path)
  if path:sub(1, #HOME + 1) == HOME .. "/" then
    return "~" .. path:sub(#HOME + 1)
  end
  return path
end

local function picker_item(worktree)
  return {
    id = worktree.path,
    title = picker_title(worktree),
    subtitle = shorten_home(worktree.path),
    icon = "branch",
  }
end

local function index_by_path(worktrees)
  local by_path = {}
  for _, worktree in ipairs(worktrees) do
    by_path[worktree.path] = worktree
  end
  return by_path
end

-- Detached worktrees would all share one tab label, so name those by directory.
local function tab_label(worktree)
  if worktree.branch == "detached" then
    return worktree.path:match("([^/]+)$")
  end
  return worktree.branch
end

local function find_by_label(items, label)
  for _, item in ipairs(items or {}) do
    if item.label == label then
      return item
    end
  end
end

local function find_repo_session(worktree)
  return find_by_label(assert(rex.call("session.list")).sessions, worktree.repo)
end

-- Methods on another session need this connection attached to it first;
-- attaching again is harmless and returns the session's current view.
local function session_view(session)
  return assert(rex.call("session.attach", { session_id = session.session_id })).view
end

local function shell_in(path)
  return rex.layout.block{ flavor = SHELL, options = { cwd = path } }
end

-- One session per repository, one tab per worktree. Returns the session and
-- window to show, creating whichever does not exist yet.
local function open_tab(worktree)
  local label = tab_label(worktree)
  local session = find_repo_session(worktree)
  if session == nil then
    local created = assert(rex.call("session.create", {
      label = worktree.repo,
      initial_windows = { { window_label = label, layout = shell_in(worktree.path) } },
    }))
    return created.session_id, created.initial_windows[1].window_id
  end
  local window = find_by_label(session_view(session).windows, label) or assert(rex.call("session.new_window", {
    session_id = session.session_id,
    window_label = label,
    layout = shell_in(worktree.path),
  }))
  return session.session_id, window.window_id
end

-- Teach zoxide about the visit so the picker ranks the repository higher next
-- time. A shell that starts in a directory never tells zoxide on its own.
-- Without zoxide, rex.exec returns nil and ranking stays alphabetical.
local function record_visit(path)
  rex.exec({ "zoxide", "add", "--", path })
end

local function pick_worktree(worktrees)
  local items = {}
  for _, worktree in ipairs(worktrees) do
    table.insert(items, picker_item(worktree))
  end
  local path = rex.ui.pick{
    title = "Open worktree",
    placeholder = "Filter worktrees",
    items = items,
  }
  return path and index_by_path(worktrees)[path]
end

-- The cleanup runs in a pane rather than in the action: it needs the person
-- to choose, can take longer than an action is allowed, and shows its
-- progress there, reporting status over OSC 7501.
-- The pane closes when git-wt exits, taking its status record with it, so
-- git-wt is asked to send the result as a desktop notification as well.
local CLEANUP_COMMAND = { "env", "GIT_WT_NOTIFY=1", GIT_WT, "--clean-all" }

local function open_cleanup_panel(ctx)
  assert(rex.session.new_split{
    anchor_id = ctx.block_id,
    direction = "vertical",
    side = "after",
    focus = true,
    layout = rex.layout.block{
      flavor = SHELL,
      label = "git-wt clean",
      options = { command = CLEANUP_COMMAND, cwd = HOME },
    },
  })
end

rex.action{
  name = "git_wt_open",
  title = "Git: Open Worktree…",
  description = "Switch to a worktree's tab in its repository's session, creating either if needed.",
  keywords = "git worktree branch repo session switch",
  run = function(ctx, args)
    local worktree = pick_worktree(git_wt("--list-all"))
    if worktree == nil then
      return
    end
    record_visit(worktree.path)
    local session_id, window_id = open_tab(worktree)
    rex.client.queue("session.select", { session_id = session_id, window_id = window_id })
  end,
}

rex.action{
  name = "git_wt_clean",
  title = "Git: Clean Up Stale Worktrees…",
  description = "Open a pane to remove worktrees whose work is merged or whose upstream is gone.",
  keywords = "git worktree remove prune stale merged clean",
  run = function(ctx, args)
    open_cleanup_panel(ctx)
  end,
}
