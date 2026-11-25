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
-- zoomed pane has focus, so opening the float clears it, and tools/return-to-caller gives it back when
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
-- REX_BLOCK names the float itself. Every tool runs inside tools/return-to-caller, which focuses
-- that pane again as the tool exits, and MDJ_REX_ZOOMED tells it the calling pane was zoomed.
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
              tools .. "return-to-caller", tools .. "upper-slots", tools .. args.tool,
            },
          },
        },
      },
    }
    if err ~= nil then error(err, 0) end
  end,
}

-- Rex keeps the Herdr app's keys, so the fingers do not change between the two.
-- dotfiles/herdr-app/.config/herdr-app/keys.json is the other half, and a key changed in one
-- changes in both. A binding here stacks over the key the app ships with, so taking a key Rex
-- uses, cmd+shift+g from Go to Directory or cmd+alt+h from Hide Others, needs nothing more.
-- Herdr's spaces are Rex's sessions. Keys Rex already ships with the shared meaning, new tab,
-- new session on cmd+shift+n, close window on cmd+shift+w, splits and the pane arrows, are not
-- repeated here.

-- The three tools, as VS Code places source control, the explorer and search.
rex.bind("cmd+shift+g", "float_tool", { tool = "lazygit.sh", title = "git" })
rex.bind("cmd+shift+e", "float_tool", { tool = "browse.sh", title = "files" })
rex.bind("cmd+shift+f", "float_tool", { tool = "find.sh", title = "fuzzy search", width = 0.8, height = 0.8 })

-- Tabs.
rex.bind("cmd+shift+h", "client.tab.previous")
rex.bind("cmd+shift+l", "client.tab.next")
rex.bind("cmd+shift+[", "client.tab.previous")
rex.bind("cmd+shift+]", "client.tab.next")
rex.bind("ctrl+shift+tab", "client.tab.previous")
rex.bind("ctrl+tab", "client.tab.next")
rex.bind("cmd+ctrl+shift+h", "client.tab.move.backward")
rex.bind("cmd+ctrl+shift+l", "client.tab.move.forward")
rex.bind("f2", "client.tab.rename")
for i = 1, 9 do
  rex.bind("cmd+" .. i, "client.tab.goto", { index = i })
end

-- Spaces, which Rex calls sessions.
rex.bind("cmd+shift+j", "session.next")
rex.bind("cmd+shift+k", "session.previous")
rex.bind("cmd+alt+]", "session.next")
rex.bind("cmd+alt+[", "session.previous")
rex.bind("cmd+ctrl+w", "session.close")
rex.bind("shift+f2", "session.rename")
-- One window with Sessions, Blocks and Activity sections, each key opening it on its own section.
-- Activity takes cmd+k from Rex's Change Session, since it is the one used most, and sessions
-- move to cmd+s. cmd+. is Rex's own Show Activity, the sidebar view, and is left alone. Herdr
-- binds neither k nor s.
rex.bind("cmd+k", "pane.view_activity")
rex.bind("cmd+s", "session.switch")
rex.bind("cmd+p", "pane.go_to")

-- Panes and the sidebar.
rex.bind("cmd+alt+h", "pane.focus.left")
rex.bind("cmd+alt+j", "pane.focus.down")
rex.bind("cmd+alt+k", "pane.focus.up")
rex.bind("cmd+alt+l", "pane.focus.right")
rex.bind("cmd+alt+enter", "pane.zoom")
rex.bind("cmd+b", "client.sidebar.toggle")
