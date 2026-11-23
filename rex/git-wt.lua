-- Rex integration for git-wt: pick a worktree from any repository under
-- GIT_WT_ROOTS and switch to its session, creating one with a shell in the
-- worktree when none exists. Installed by `./setup.sh --rex`.

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

local function session_label(worktree)
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
      title = session_label(worktree),
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

local function find_session(label)
  local listed = assert(rex.call("session.list"))
  for _, session in ipairs(listed.sessions or {}) do
    if session.label == label then
      return session.session_id
    end
  end
end

local function create_session(label, path)
  local created = assert(rex.call("session.create", {
    label = label,
    initial_windows = {
      { layout = rex.layout.block{ flavor = SHELL, options = { cwd = path } } },
    },
  }))
  return created.session_id
end

rex.action{
  name = "git_wt_open",
  title = "Git: Open Worktree…",
  description = "Switch to a worktree's session, creating it with a shell there if needed.",
  keywords = "git worktree branch repo session switch",
  run = function(ctx, args)
    local worktree = pick_worktree(list_worktrees())
    if worktree == nil then
      return
    end
    local label = session_label(worktree)
    local session_id = find_session(label) or create_session(label, worktree.path)
    rex.client.queue("session.select", { session_id = session_id })
  end,
}
