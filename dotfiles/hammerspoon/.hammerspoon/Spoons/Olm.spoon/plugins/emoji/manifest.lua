-- Emoji, what it declares about itself.
--
-- Pure data, loaded without loading the plugin. Nothing here is read at runtime by the
-- plugin itself, it is read by Olm's root, which turns it into wiring, and by the setup
-- script, which turns the tool lines into an install proposal.
return {
  needs = {
    -- A glyph is PASTED rather than typed, because a synthesized keystroke mangles an
    -- astral character in a terminal and in some native apps. This used to be declared as
    -- a sibling need naming clipboard.pasteText, which read as a plugin to plugin loan.
    -- It is not one. The clipboard plugin dropped its outward pasteText and copySelection
    -- wrappers, they are gone from that plugin entirely, and the composition root never
    -- asked the clipboard plugin for this at all. It reaches Olm's own lib.paste module
    -- directly and falls back to a typed keystroke when that module is absent, so this is
    -- a lib need on the shared insertion engine rather than a sibling need on a plugin
    -- that no longer offers it. Optional, since typing is a worse but working fallback,
    -- which is exactly what the root's own fallback closure already does.
    lib = {
      onInsert = { from = "paste", member = "pasteText", policy = "optional" },
    },
    -- These build the vendored dataset and are not needed to USE the picker, which is
    -- what `stage` says. Without the split an install list would tell someone to fetch a
    -- dataset builder before they can pick an emoji.
    tools = {
      { name = "jq", kind = "path", policy = "optional", stage = "dev",
        reason = "reshaping both upstream sources into the vendored dataset",
        origin = { brew = "jq" } },
      { name = "perl", kind = "path", policy = "optional", stage = "dev",
        reason = "parsing the Unicode Character Database into candidate rows",
        origin = { macos = "ships with the system" } },
    },
  },

  -- What a launcher scope may reach, so a typed alias lists the same rows the picker does
  -- and choosing one does the same thing. Handing the pair out is what stops a second copy
  -- of the parse existing.
  provides = {
    rows = "rows",
    select = "select",
  },

  -- What this plugin proposes for itself on a machine that has said nothing. The leader is
  -- a ROLE rather than a physical key, so moving the app leader onto SUPER carries this
  -- with it and no manifest changes.
  --
  -- J rather than E because Hyper and E is already the menu search handoff combo. The
  -- aliases are the letter anyone would try first plus the whole word.
  defaults = {
    leader = "app",
    key = "j",
    description = "Emoji picker",
    glyph = "😀",
    aliases = { "e", "emoji" },
  },

  -- It has a chooser, so it takes the shared navigation, its predicate, its registry
  -- entry, and its docked shortcut panel with nothing further stated. Only the primary key
  -- is named, since j, k, and x mean the same thing in every list here and the predicate
  -- name and priority follow from the context name.
  surface = {
    context = "emoji",
    -- This plugin's configure reads the docked panel's three callbacks nested under one
    -- field rather than as three flat ones, so the shape is named here. Four plugins
    -- disagree about this and the disagreement lives in their own configure contracts,
    -- so it has to be declared. Assuming the flat form silently removed the panel from
    -- every one of them while handing each three fields it never reads.
    panelAs = "shortcutPanel",
    primary = { action = "insertSelected", description = "Insert" },
  },

  -- show, rows, insert and lists are all colon methods, obj:show(), obj:rows(query),
  -- obj:insert(glyph) and obj:lists(), so every one of them takes the default call. guard
  -- names lists because this plugin picks a backend at start and the system Character Viewer
  -- has no rows of its own to hand over, so a scope built regardless of which backend won
  -- would open onto an empty list rather than the plain unscoped search that already works
  -- for that backend. matcher is false because the scope matches over a hidden haystack of
  -- names, shortcodes, tags and categories the shared word or fuzzy strategies never see.
  registry = {
    row = { category = "Tools" },
    open = "show",
    surface = "surface",
    hosted = true,
    shortcut = "leader",
    scope = {
      guard = "lists",
      matcher = false,
      rows = "rows",
      run = "insert",
    },
  },
}
