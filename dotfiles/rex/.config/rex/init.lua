-- Rex reads this file at server start and on `rex config reload`, never on its own, so a change
-- here shows only after that reload. dotfiles/rex/AGENTS.md has the rest.

local terminal = "com.superlogical.terminal"
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local tools = config_home .. "/rex/tools/"

-- Where the pane the key was pressed in sits. The foreground process is the shell at its prompt
-- or whatever runs in front of it, and its directory is a plain path, where the reported pwd can
-- be a file URL. Home is the answer when neither can be read.
local function pane_cwd(block_id)
  local p = rex.block.call(terminal, "process", { block_id = block_id })
  if p ~= nil then
    if p.foreground ~= nil and p.foreground.cwd ~= nil then return p.foreground.cwd end
    if p.child ~= nil and p.child.cwd ~= nil then return p.child.cwd end
  end
  return os.getenv("HOME")
end

-- Whether the pane the key was pressed in fills its window. Rex keeps a zoom only while the
-- zoomed pane has focus, so opening the float clears it, and tools/keep-zoom gives it back when
-- the tool exits.
local function pane_zoomed(session_id, block_id)
  if session_id == nil or block_id == nil then return false end
  local view = rex.session.view{ session_id = session_id }
  if view == nil then return false end
  for _, w in ipairs(view.windows or {}) do
    if w.zoomed_block_id == block_id then return true end
  end
  return false
end

-- One floating pane over the current tab, running one tool in the calling pane's directory. A
-- tool is the script name and nothing else, so adding one is a script in tools/ and a binding
-- below. The pane closes when the tool exits, and the layer goes with it since the pane is its
-- only block. MDJ_REX_TARGET names the pane the key was pressed in, because inside the float
-- REX_BLOCK names the float itself. Every tool runs inside tools/keep-zoom, and MDJ_REX_ZOOMED
-- tells it the calling pane was zoomed.
rex.action{
  name  = "float_tool",
  title = "Open a Tool in a Floating Pane",
  args  = { tool = "string", title = "string", width = "number?", height = "number?" },
  run   = function(ctx, args)
    local w, h = args.width or 0.9, args.height or 0.9
    local _, err = rex.session.new_layer{
      bounds = { (1 - w) / 2, (1 - h) / 2, w, h },
      focus  = true,
      layout = {
        block = {
          flavor  = terminal .. ".shell",
          label   = args.title,
          options = {
            cwd     = pane_cwd(ctx.block_id),
            command = {
              "env",
              "MDJ_REX_TARGET=" .. (ctx.block_id or ""),
              "MDJ_REX_ZOOMED=" .. (pane_zoomed(ctx.session_id, ctx.block_id) and "1" or ""),
              tools .. "keep-zoom", tools .. args.tool,
            },
          },
        },
      },
    }
    if err ~= nil then error(err, 0) end
  end,
}

-- The same prefix and the same keys as herdr and tmux, so the fingers do not change between them.
-- Pressing the prefix twice sends it on, for a tmux running inside a Rex pane.
rex.bind("alt+z>alt+g", "float_tool", { tool = "lazygit.sh", title = "git" })
rex.bind("alt+z>f", "float_tool", { tool = "find.sh", title = "fuzzy search", width = 0.8, height = 0.8 })
rex.bind("alt+z>alt+f", "float_tool", { tool = "browse.sh", title = "files" })
rex.bind("alt+z>alt+z", "pane.send_key", { key = "alt+z" })

-- Single chords for the same tools, beside the prefix keys. Cmd and shift with g is taken by
-- Rex's own Go to Directory, which wins over this file, so lazygit takes l instead.
rex.bind("cmd+shift+f", "float_tool", { tool = "find.sh", title = "fuzzy search", width = 0.8, height = 0.8 })
rex.bind("cmd+shift+e", "float_tool", { tool = "browse.sh", title = "files" })
rex.bind("cmd+shift+l", "float_tool", { tool = "lazygit.sh", title = "git" })
