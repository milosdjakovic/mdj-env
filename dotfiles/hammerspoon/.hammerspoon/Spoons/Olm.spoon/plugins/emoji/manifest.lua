-- Emoji, what it declares about itself.
--
-- Pure data, loaded without loading the plugin. Nothing here is read at runtime by the
-- plugin itself, it is read by Olm's root, which turns it into wiring, and by the setup
-- script, which turns the tool lines into an install proposal.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Emoji & Symbol Picker",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The icons this plugin names, in the emoji set and the SF Symbol set. The one named for the
  -- plugin is its identity icon, which the launcher row and the scoped list both wear.
  -- The glyphs in the picker's own rows are content, table specs of the emoji alone, and are
  -- never declared here.
  icons = {
    emoji = { emoji = "😀", sf = "face.smiling" },
  },

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
      -- hs is the Hammerspoon CLI itself, and it arrives on PATH the way every other cask
      -- shipped command here does. The cask declares the copy inside the app bundle as a
      -- binary artifact, so Homebrew symlinks it into the prefix as it installs the app. This
      -- said manual for a long time, and named cliInstall as the step that puts it there,
      -- which nobody had ever run on the machine that claim described.
      { name = "hs", kind = "path", policy = "optional", stage = "dev", unit = "regenerate",
        reason = "rendering every candidate glyph to drop the ones that draw as a box, and writing the dataset",
        origin = { cask = "hammerspoon" } },
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
  -- aliases are the letter anyone would try first, two letters for the same reach, and the
  -- whole word.
  defaults = {
    leader = "app",
    -- The open key, a bindings row whose action is open, on the leader above.
    bindings = { { action = "open", key = "j" } },
    description = "Emoji & symbol picker",
    icon = "emoji",
    aliases = { "e", "em", "emoji" },
  },

  -- It has a chooser, so it takes the shared navigation, its predicate, its registry
  -- entry, and its place in the action bar with nothing further stated. Only the primary key
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
  -- No matcher, so the list inherits the shared search, phase three of
  -- docs/PLAN-UNIFIED-SEARCH.md on 2026-10-17. Each row declares its name, an emoji its
  -- shortcode aliases as further names, and its tags and category as keywords, and an emoji
  -- ranks above a symbol by tier, so the hidden haystack this tool once scanned itself is now
  -- fields the engine reads.
  -- placeholder resolves once, at register, to the hammerspoon backend's own wording, the only
  -- backend ever shown through this presentation.
  --
  -- rowLimit is the most rows shown, cut after ranking, so the best rows of a broad query are
  -- the ones kept and every glyph stays findable by typing. The supplier hands over all of the
  -- several thousand rows, and the provider styles every row it is handed, so the limit is
  -- what keeps a keystroke cheap and bounds the icons a view renders.
  presentation = {
    rows = { member = "rows", call = "method" },
    select = { member = "insert", call = "method" },
    placeholder = { member = "placeholder", call = "method" },
    rowLimit = 100,
  },

  -- show, rows, insert and lists are all colon methods, obj:show(), obj:rows(query),
  -- obj:insert(glyph) and obj:lists(), so every one of them takes the default call. guard
  -- names lists because this plugin picks a backend at start and the system Character Viewer
  -- has no rows of its own to hand over, so a scope built regardless of which backend won
  -- would open onto an empty list rather than the plain unscoped search that already works
  -- for that backend. The scope declares no matcher and the same rowLimit as the presentation
  -- above, so the query scope ranks the same rows the same way and keeps the same number.
  -- surface is no longer declared, host/stage's own surfaceFor
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
      rows = "rows",
      run = "insert",
      rowLimit = 100,
    },
  },
}
