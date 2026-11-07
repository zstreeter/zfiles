-- Adapter for herdr, the terminal workspace manager nvim runs inside — the
-- only place that knows herdr's CLI. It registers itself as a sidekick session
-- backend (sidekick ships tmux and zellij), so AI CLIs run in a real herdr
-- pane instead of an nvim `:terminal`.
--
-- Why that matters: nvim's libvterm drops the kitty graphics escapes that
-- @fadouse/pi-math emits for rendered LaTeX, and pi-tui refuses images
-- outright when $TMUX is set. A herdr pane is the only surface here that
-- draws them.
local Config = require("sidekick.config")
local Util = require("sidekick.util")

---@class sidekick.cli.muxer.Herdr: sidekick.cli.Session
---@field herdr_pane_id string
local M = {}
M.__index = M

-- pi-tui and pi-math both sniff TERM_PROGRAM/TERM to decide whether images are
-- possible, and herdr sets TERM=xterm-256color while stripping the outer
-- terminal's vars — so with no help neither sees a match and LaTeX silently
-- degrades to text. herdr embeds ghostty's terminal core (kitty protocol,
-- unicode virtual placeholders included), so declaring ghostty describes the
-- emulator actually parsing these escapes. It is not a claim about the outer
-- terminal; wezterm only ever sees herdr's re-rendered output.
-- ponytail: one env var covers every kitty-protocol CLI, no per-tool config.
local IMAGE_ENV = { TERM_PROGRAM = "ghostty" }

--- True when this nvim is running inside a herdr-managed pane.
function M.available()
  return vim.env.HERDR_ENV == "1" and vim.fn.executable("herdr") == 1
end

--- Run a herdr CLI command and return its decoded `result` object.
---@param cmd string[]
---@return table?
local function api(cmd)
  local _, out = Util.exec(cmd, { notify = false })
  if not out then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, out)
  return ok and type(decoded) == "table" and decoded.result or nil
end

---@return table[]
function M.panes()
  local res = api({ "herdr", "pane", "list" })
  return res and res.panes or {}
end

--- Open a focused herdr pane, optionally running a command in it.
---@param cmd? string[]
function M.open_pane(cmd)
  if not M.available() then
    Util.error("herdr is unavailable")
    return
  end

  local res = api({
    "herdr",
    "pane",
    "split",
    "--current",
    "--direction",
    "right",
    "--ratio",
    "0.45",
    "--cwd",
    vim.fn.getcwd(),
    "--focus",
  })
  local pane = res and res.pane
  if not pane then
    Util.error("herdr: failed to split a pane")
    return
  end

  if cmd then
    local run = { "herdr", "pane", "run", pane.pane_id }
    vim.list_extend(run, cmd)
    Util.exec(run)
  end
end

--- herdr classifies the agent running in each pane itself, so unlike the tmux
--- backend there is no process tree to walk — a pane's `agent` is the tool name.
---@param panes? table[] injectable for tests; defaults to a live `pane list`
function M.sessions(panes)
  local tools = Config.tools()
  local ret = {} ---@type sidekick.cli.session.State[]
  for _, pane in ipairs(panes or M.panes()) do
    -- herdr's agent labels match sidekick's tool names for the tools that
    -- exist in both; anything herdr knows and sidekick doesn't is skipped.
    local tool = pane.agent and tools[pane.agent]
    if tool then
      ret[#ret + 1] = {
        id = ("herdr %s"):format(pane.pane_id),
        cwd = pane.foreground_cwd or pane.cwd,
        tool = tool,
        herdr_pane_id = pane.pane_id,
        mux_session = pane.workspace_id,
      }
    end
  end
  return ret
end

function M:init()
  -- herdr owns the pane's window; it is never drawn inside nvim.
  self.external = true
end

--- Never returns a Cmd: attaching would pull the pane into an nvim terminal,
--- which is exactly the libvterm surface that loses the images.
function M:attach()
  -- Pane IDs are valid agent targets once herdr recognizes the agent; before
  -- that this is a no-op, and the pane is on screen either way.
  Util.exec({ "herdr", "agent", "focus", self.herdr_pane_id }, { notify = false })
end

function M:start()
  local split = Config.cli.mux.split
  local cmd = {
    "herdr",
    "pane",
    "split",
    "--current",
    "--direction",
    split.vertical and "right" or "down",
    "--ratio",
    tostring(split.size),
    "--cwd",
    self.cwd,
    "--no-focus",
  }
  for key, value in pairs(vim.tbl_extend("force", IMAGE_ENV, self.tool.env or {})) do
    if value ~= false then -- `false` means unset, and a fresh pane has nothing to unset
      vim.list_extend(cmd, { "--env", ("%s=%s"):format(key, tostring(value)) })
    end
  end

  local res = api(cmd)
  local pane = res and res.pane
  if not pane then
    Util.error("herdr: failed to split a pane for " .. self.tool.name)
    return
  end

  self.herdr_pane_id = pane.pane_id
  self.id = ("herdr %s"):format(pane.pane_id)
  self.mux_session = pane.workspace_id
  self.started = true

  -- `pane split` takes no command, so the tool is launched into the new shell.
  local run = { "herdr", "pane", "run", pane.pane_id }
  vim.list_extend(run, self.tool.cmd)
  Util.exec(run)
  Util.info(("Started **%s** in a new herdr pane"):format(self.tool.name))
end

function M:is_running()
  for _, pane in ipairs(M.panes()) do
    if pane.pane_id == self.herdr_pane_id then
      return true
    end
  end
  return false
end

function M:send(text)
  Util.exec({ "herdr", "pane", "send-text", self.herdr_pane_id, text })
end

function M:submit()
  Util.exec({ "herdr", "pane", "send-keys", self.herdr_pane_id, "Enter" })
end

function M:dump()
  local _, out = Util.exec({
    "herdr",
    "pane",
    "read",
    self.herdr_pane_id,
    "--format",
    "ansi",
    "--lines",
    -- mux.dump was only added to sidekick in Apr 2026; the lockfile pin may
    -- predate it, and `--lines nil` would be sent verbatim. 2000 is upstream's
    -- default.
    tostring(Config.cli.mux.dump or 2000),
  }, { notify = false })
  return out
end

--- Register with sidekick and make it the active backend. Called from the
--- sidekick spec after `setup()`, because sidekick validates `mux.backend` (deferred)
--- against its own two builtins and would reject "herdr" during setup.
function M.setup()
  if not M.available() then
    return
  end
  require("sidekick.cli.session").register("herdr", M)
  -- sidekick validates mux.backend in a vim.schedule callback from setup();
  -- queue the swap behind it or it rejects "herdr" with an error popup.
  vim.schedule(function()
    Config.cli.mux.backend = "herdr"
  end)
end

return M
