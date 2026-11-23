-- Rex integration for git-wt: pick a worktree from any repository under
-- GIT_WT_ROOTS and switch to its tab in the repository's session, creating
-- the session or the tab, with a shell in the worktree, when missing.
-- Installed by `./setup.sh --rex`.

local GIT_WT = os.getenv("HOME") .. "/.local/bin/git-wt"
-- Listing ~100 repositories takes well under a second; the margin covers a
-- cold disk cache without leaving the palette hanging indefinitely.
local LIST_TIMEOUT_SECONDS = 30
local SHELL = "com.superlogical.terminal.shell"
local HOME = os.getenv("HOME")

local function list_worktrees()
  local result, err = rex.exec({ GIT_WT, "--list-all" }, { timeout = LIST_TIMEOUT_SECONDS })
  if result == nil then
    error("git-wt: " .. err)
  end
  if not result.ok then
    error("git-wt --list-all failed: " .. result.stderr)
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

local function pick_worktree(worktrees)
  local items, by_path = {}, {}
  for _, worktree in ipairs(worktrees) do
    by_path[worktree.path] = worktree
    table.insert(items, {
      id = worktree.path,
      title = picker_title(worktree),
      subtitle = shorten_home(worktree.path),
      icon = "branch",
    })
  end
  local path = rex.ui.pick{
    title = "Open worktree",
    placeholder = "Filter worktrees",
    items = items,
  }
  return path and by_path[path]
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

local function shell_in(path)
  return rex.layout.block{ flavor = SHELL, options = { cwd = path } }
end

-- One session per repository, one tab per worktree. Returns the session and
-- window to show, creating whichever does not exist yet.
local function open_tab(worktree)
  local label = tab_label(worktree)
  local session = find_by_label(assert(rex.call("session.list")).sessions, worktree.repo)
  if session == nil then
    local created = assert(rex.call("session.create", {
      label = worktree.repo,
      initial_windows = { { window_label = label, layout = shell_in(worktree.path) } },
    }))
    return created.session_id, created.initial_windows[1].window_id
  end
  -- Methods on another session need this connection attached to it first;
  -- attaching again is harmless and returns the session's current view.
  local view = assert(rex.call("session.attach", { session_id = session.session_id })).view
  local window = find_by_label(view.windows, label) or assert(rex.call("session.new_window", {
    session_id = session.session_id,
    window_label = label,
    layout = shell_in(worktree.path),
  }))
  return session.session_id, window.window_id
end

rex.action{
  name = "git_wt_open",
  title = "Git: Open Worktree…",
  description = "Switch to a worktree's tab in its repository's session, creating either if needed.",
  keywords = "git worktree branch repo session switch",
  run = function(ctx, args)
    local worktree = pick_worktree(list_worktrees())
    if worktree == nil then
      return
    end
    local session_id, window_id = open_tab(worktree)
    rex.client.queue("session.select", { session_id = session_id, window_id = window_id })
  end,
}
