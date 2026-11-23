-- Rex integration for git-wt. Installed by `./setup.sh --rex`.
--
-- Git: Open Worktree… picks a worktree from any repository under
-- GIT_WT_ROOTS and switches to its tab in the repository's session,
-- creating the session or the tab, with a shell in the worktree, if missing.
--
-- Git: Clean Up Stale Worktrees… offers the worktrees whose work is merged
-- or whose upstream branch is gone, removes the ones ticked, and closes
-- their tabs.

local HOME = os.getenv("HOME")
local GIT_WT = HOME .. "/.local/bin/git-wt"
-- Listing takes under a second and the stale check a few seconds on ~100
-- repositories; the margin covers a cold disk cache without leaving the
-- palette hanging indefinitely.
local LIST_TIMEOUT_SECONDS = 30
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

-- Closes the worktree's tab, and the repository's session with it when that
-- was the last tab, since an empty session is of no use.
local function close_tab(worktree)
  local session = find_repo_session(worktree)
  if session == nil then
    return
  end
  local windows = session_view(session).windows or {}
  local window = find_by_label(windows, tab_label(worktree))
  if window == nil then
    return
  end
  if #windows == 1 then
    assert(rex.call("session.destroy", { session_id = session.session_id }))
  else
    assert(rex.call("session.close_window", { session_id = session.session_id, window_id = window.window_id }))
  end
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

-- Dirty worktrees are listed so nothing stale is hidden, but left unticked:
-- git refuses to remove them without --force, which this never passes.
local function pick_stale(stale)
  local items = {}
  for _, worktree in ipairs(stale) do
    local item = picker_item(worktree)
    item.detail = worktree.dirty and (worktree.reason .. ", dirty") or worktree.reason
    item.selected = not worktree.dirty
    table.insert(items, item)
  end
  return rex.ui.pick{
    title = "Remove stale worktrees",
    placeholder = "Filter worktrees",
    confirm = "Remove",
    multiple = true,
    items = items,
  }
end

local function remove_worktree(worktree)
  local result, err = rex.exec({ "git", "-C", worktree.path, "worktree", "remove", worktree.path })
  if result == nil then
    return err
  end
  if not result.ok then
    return result.stderr
  end
  close_tab(worktree)
end

-- Rex has no notification call, so failures are shown as a list to dismiss.
local function show_failures(failures)
  if #failures > 0 then
    local title = #failures == 1 and "1 worktree was not removed"
      or (#failures .. " worktrees were not removed")
    rex.ui.pick{
      title = title,
      confirm = "Dismiss",
      items = failures,
    }
  end
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
  description = "Remove worktrees whose work is merged or whose upstream is gone, and close their tabs.",
  keywords = "git worktree remove prune stale merged clean",
  run = function(ctx, args)
    local stale = git_wt("--list-stale")
    if #stale == 0 then
      rex.ui.pick{ title = "No stale worktrees", confirm = "Dismiss", items = {} }
      return
    end
    local chosen = pick_stale(stale)
    if chosen == nil then
      return
    end
    local by_path, failures = index_by_path(stale), {}
    for _, path in ipairs(chosen) do
      local problem = remove_worktree(by_path[path])
      if problem then
        table.insert(failures, { id = path, title = picker_title(by_path[path]), subtitle = problem })
      end
    end
    show_failures(failures)
  end,
}
