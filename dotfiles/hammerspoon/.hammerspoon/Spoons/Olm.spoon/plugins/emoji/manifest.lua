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
    --
    -- dot, because lib/paste.lua exports plain functions, function M.pasteText(text). Left to
    -- the default method binding it arrives with the paste module itself in the first
    -- parameter and the glyph pushed along one, so choosing an emoji inserted nothing and
    -- raised nothing either, which is how the mismatch stays invisible in Lua.
    lib = {
      onInsert = { from = "paste", member = "pasteText", call = "dot", policy = "optional" },
    },
    -- One root computed word, the trickle migration onto the shared stage. stagePresent is
    -- the hotkey door this plugin's own show reaches for when the winning backend owns a
    -- list, which only the hammerspoon backend ever does. Optional, and it degrades to an
    -- inert press rather than a crash, since a plugin asking before the stage's own
    -- configure has run is a wiring defect rather than a state a key press should silently
    -- swallow.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the leader key and the special row dispatch both open nothing when the " ..
                 "winning backend owns a list, since show has no other way to reach the " ..
                 "shared stage" },
    },
    -- These build the vendored dataset and are not needed to USE the picker, which is
    -- what `stage` says. Without the split an install list would tell someone to fetch a
    -- dataset builder before they can pick an emoji.
    tools = {
      { name = "jq", kind = "path", policy = "optional", stage = "dev", unit = "regenerate",
        reason = "reshaping both upstream sources into the vendored dataset",
        origin = { brew = "jq" } },
      { name = "perl", kind = "path", policy = "optional", stage = "dev", unit = "regenerate",
        reason = "parsing the Unicode Character Database into candidate rows",
        origin = { macos = "ships with the system" } },
      -- hs is the Hammerspoon CLI itself, which does not arrive on PATH the way a brew
      -- formula does. The cask ships it inside the app bundle, and cliInstall is the one
      -- step that symlinks it out, so the origin says that rather than naming a package
      -- manager that never touches this tool.
      { name = "hs", kind = "path", policy = "optional", stage = "dev", unit = "regenerate",
        reason = "rendering every candidate glyph to drop the ones that draw as a box, and writing the dataset",
        origin = { manual = "the Hammerspoon cask ships the CLI inside the app, run hs.ipc.cliInstall() once from the Hammerspoon console to symlink it onto the PATH" } },
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
    primary = { action = "insertSelected", description = "Insert" },
  },

  -- The presentation contract, contract v2, docs/BRIEF-CONTRACT-V2.md. rows and select are
  -- this plugin's own colon methods, so every field below says call = method, stated
  -- outright, never the bare string shorthand this contract allows everywhere else a member
  -- is not a presentation's own. Both simply forward to whichever backend won, obj:rows and
  -- obj:insert already having done exactly that before the stage existed to ask for either.
  --
  -- matcher is false, the identical opt out the retired Chooser.new block already declared,
  -- since this tool filters over a hidden haystack, the folded name, aliases, tags, and
  -- category, with its own token AND scan and ranking, never over the visible title and
  -- subtitle the shared matcher would see. placeholder resolves once, at register, to the
  -- hammerspoon backend's own wording, the only backend ever shown through this presentation.
  presentation = {
    rows = { member = "rows", call = "method" },
    select = { member = "insert", call = "method" },
    placeholder = { member = "placeholder", call = "method" },
    matcher = false,
  },

  -- show, rows, insert and lists are all colon methods, obj:show(), obj:rows(query),
  -- obj:insert(glyph) and obj:lists(), so every one of them takes the default call. guard
  -- names lists because this plugin picks a backend at start and the system Character Viewer
  -- has no rows of its own to hand over, so a scope built regardless of which backend won
  -- would open onto an empty list rather than the plain unscoped search that already works
  -- for that backend. matcher is false for the identical reason presentation.matcher above
  -- is, since the scope matches over the same hidden haystack the shared word or fuzzy
  -- strategies never see. surface is no longer declared, host/stage's own surfaceFor
  -- answering the five generic nav verbs now that presentation above exists, and this
  -- plugin binds no verb beyond them, unconditionally, matching the old NOOP_SURFACE's own
  -- always-false isShowing for the macos and custom backends since neither is ever what the
  -- stage is showing.
  registry = {
    row = { category = "Tools" },
    open = "show",
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
