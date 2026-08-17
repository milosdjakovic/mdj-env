-- TextCase, what it declares about itself.
--
-- The interesting one of the prototype three, because it is the plugin whose whole reason
-- for working depends on two mechanisms it does not own. Both are declared and injected,
-- so this plugin still names no clipboard.

-- The registry and every sibling lookup know this plugin as textCase, camel cased, while
-- the directory beside this file is textcase, lowercase.
return {
  name = "textCase",

  needs = {
    -- Reading the selection and writing the result back in place. Both used to be declared
    -- as sibling needs naming clipboard.copySelection and clipboard.pasteText, which read as
    -- a loan from the clipboard plugin. It is not one. The clipboard plugin dropped its
    -- outward pasteText and copySelection wrappers, they are gone from that plugin entirely,
    -- and the composition root never asked the clipboard plugin for either. It reaches Olm's
    -- own lib.paste module directly for both, and falls back to a typed keystroke with no
    -- read at all when that module is absent, the same degradation the emoji insert takes.
    -- So both are lib needs on the shared insertion engine, not sibling needs on a plugin
    -- that no longer offers them.
    --
    -- Both say dot, and both are useless without it. Every function lib/paste.lua exports is
    -- a plain one, function M.copySelection(cb), so a member handed over with the default
    -- method binding arrives with the paste module itself wedged into the first parameter and
    -- every real argument shifted along one. Reading a selection then called its own module
    -- table as the callback, so the read never came back and the picker this plugin opens
    -- after the read never opened, and applying a case pasted the module instead of the text.
    -- Lua raises nothing at all for either, it simply passes what it was given.
    lib = {
      read  = { from = "paste", member = "copySelection", call = "dot", policy = "optional" },
      apply = { from = "paste", member = "pasteText",     call = "dot", policy = "optional" },
    },
  },

  -- No `provides`, deliberately. A launcher scope cannot read your selection, since that
  -- needs the keyboard in the app the launcher is covering, so a scoped copy could list
  -- every case but never preview your own text in one. The preview is most of the reason
  -- to open it, so the alias was tried and removed rather than kept as a lesser copy.
  -- This absence is the decision, not an omission.

  -- Opened from the launcher only, so it proposes no key at all. A default of nothing is
  -- still a default, and it is why the file says so rather than leaving the field out.
  defaults = {
    description = "Text Case",
    launcherRow = true,
  },

  surface = {
    context = "textCase",
    -- This plugin's configure reads the docked panel's three callbacks nested under one
    -- field rather than as three flat ones, so the shape is named here. Four plugins
    -- disagree about this and the disagreement lives in their own configure contracts,
    -- so it has to be declared. Assuming the flat form silently removed the panel from
    -- every one of them while handing each three fields it never reads.
    panelAs = "shortcutPanel",
    primary = { action = "insertSelected", description = "Apply" },
  },

  -- show and surface are both colon methods, obj:show() and obj:surface(), so open takes
  -- the default call.
  registry = {
    row = { category = "Text", detail = "recase the selection in place", glyph = "🔠" },
    open = "show",
    surface = "surface",
  },
}
