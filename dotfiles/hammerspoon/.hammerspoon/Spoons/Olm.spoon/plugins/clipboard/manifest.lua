-- ClipboardHistory, what it declares about itself.
--
-- The history and its paste back both run through the shared insertion engine at
-- lib/paste.lua, so this plugin borrows a lib capability the same way BrowserTabs
-- borrows recency. It once also handed pasteText and copySelection onward to Emoji
-- and TextCase as siblings, but that door is gone, the outward wrappers were deleted
-- from manager/init.lua and every consumer now reaches lib/paste.lua directly through
-- the composition root rather than through this plugin, so this manifest claims
-- nothing that would say otherwise. Video previews are the one true external
-- dependency, and they are optional, a still frame or a text block always renders
-- even with neither tool present.
return {
  needs = {
    -- The engine every paste and every selection read runs through, the pasteboard
    -- snapshot, the restore, and the self capture guard all live there. Required,
    -- because without it there is no insertion mechanism left to fall back to, the
    -- whole manager is built on this one primitive rather than merely helped by it.
    --
    -- hyperKey is optional, read by this plugin's own outer configure rather than by
    -- the manager below. Without it a reveal falls back to the literal combo, so a
    -- provider that must wait for Hyper to release before firing simply never waits.
    lib = {
      paste = { from = "paste", policy = "required" },
      hyperKey = { from = "hyperkey", policy = "optional" },
    },
    tools = {
      { name = "ffmpeg", kind = "path", policy = "optional",
        reason = "video clipboard previews",
        origin = { brew = "ffmpeg" } },
      { name = "ffprobe", kind = "path", policy = "optional",
        reason = "reading a video duration so a preview frame is picked mid clip",
        origin = { brew = "ffmpeg" } },
    },
    -- The external backend this plugin cannot build for itself, and the one surface it must
    -- not draw for itself. Everything else the outer configure needs, the paste primitive
    -- above, the reveal routing, is either a lib capability or plain policy this file owns.
    data = {
      shortcut = { source = "user", policy = "optional",
        breaks = "the shortcut backed provider, and any app it would have been gated "
          .. "on, never joins the reveal chain, so an external clipboard manager bound "
          .. "to a combo can never answer Hyper plus X ahead of the native one" },
      -- One line of feedback, drawn by whoever owns the overlay surface. Not decoration. Two of
      -- this plugin's actions change state a person cannot otherwise see, an entry growing
      -- offscreen and a position in a walk through history, and this message is the whole of
      -- what tells them anything happened.
      --
      -- Optional because both actions still do their work without it, which is precisely why its
      -- absence went unnoticed. They worked perfectly, and silently.
      notify = { source = "root", policy = "optional",
        breaks = "appending to an entry and stepping back through history both happen in "
          .. "silence, so the two actions whose result is otherwise invisible look exactly "
          .. "like a key that did nothing" },
    },
  },

  -- No provides. The manager is not itself scoped by an alias.

  -- Hyper plus X opens the native manager. No glyph and no aliases are set on this
  -- entry in config/keys.lua, unlike most of the other pickers, so none are stated
  -- here either.
  defaults = {
    leader = "app",
    key = "X",
    description = "Clipboard history",
  },

  -- Append copy and paste next sit on their own global combos rather than on this
  -- context, so they are a separate concern from the picker surface below and are
  -- left out of this manifest, which only speaks for the chooser.
  surface = {
    context = "clipboard",
    primary = { action = "insertSelected", description = "Paste" },
    extra = {
      -- Cmd is the sub modifier within Hyper, so these scroll the preview pane
      -- while the bare keys still move the highlight.
      { key = "j", mods = { "cmd" }, action = "scrollPreviewDown", description = "Scroll preview down" },
      { key = "k", mods = { "cmd" }, action = "scrollPreviewUp",   description = "Scroll preview up" },
      { key = "a", action = "appendSelected", description = "Append to batch", glyph = "➕" },
      { key = "d", action = "deleteSelected", description = "Delete", glyph = "🗑️" },
    },
    -- Entries here are prose and code searched from the inside, a real remembered
    -- word rather than an abbreviation of a short label, so the words matcher fits
    -- and fuzzy would only cost more for less. The manager still opts its own
    -- Chooser instance out of the atom's own ranking, since it parses a type prefix
    -- off the query itself, but it wants the shared matching value handed to it
    -- anyway to score the free text part, which is what makes the pane worth having.
    matcher = "words",
    -- The docked companion pane is most of what this picker is, the live preview of
    -- whatever is highlighted, so it earns the reserved room rather than going without.
    pane = true,
  },

  -- Configure alone leaves this plugin silent. Every field the picker needs, the
  -- factory, the theme, the matcher, the panel triple and the pane, along with the
  -- insertion engine itself, arrives on the manager submodule rather than on this
  -- plugin's own root, and nothing here configures that submodule internally, so
  -- the whole thing is stated as wiring rather than assumed from configure alone.
  wiring = {
    { target = "manager", method = "configure" },
    { target = "manager", method = "start" },
  },

  -- The base Hyper chord opens this plugin's own root, a colon method, so open needs no
  -- call convention beyond the default. appendCopy and pasteNext belong to no plugin, they
  -- are named actions this manager's own submodule answers as plain dot called functions
  -- with no arguments, and each sits on a global combination rather than on the Hyper
  -- leader, since that is the only place either has ever lived.
  registry = {
    row = { category = "Clipboard", glyph = "📋" },
    open = "open",
    surface = "manager",
    shortcut = "leader",
    --
    -- Both ship a key of their own, which is the one thing this block was missing. A command
    -- belongs to no plugin DIRECTORY, so the plan has no effective entry to resolve a key from
    -- the way it does for a tool's own open key, and nothing anywhere else held an answer
    -- either, so a fresh install bound neither and said so twice in the console. Control and
    -- Alt rather than a Hyper chord because both act on whatever was frontmost a moment ago
    -- rather than on a list that is already open, a different gesture that wants a plain
    -- global combination, and it is the only place either has ever lived.
    commands = {
      appendCopy = {
        fn = { member = "manager.appendCopy", call = "dot" },
        key = "C", mods = { "ctrl", "alt" },
        row = { category = "Clipboard", chord = "modifier", glyph = "➕",
          description = "Append copy",
          keywords = "append copy add selection accumulate" },
        shortcut = "global",
      },
      pasteNext = {
        fn = { member = "manager.pasteNext", call = "dot" },
        key = "V", mods = { "ctrl", "alt" },
        row = { category = "Clipboard", chord = "modifier", glyph = "⏩",
          description = "Paste next",
          keywords = "paste next sequential walk history" },
        shortcut = "global",
      },
    },
  },
}
