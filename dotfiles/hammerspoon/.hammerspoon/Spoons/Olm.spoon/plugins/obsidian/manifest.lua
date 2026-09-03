-- Obsidian, what it declares about itself.
--
-- A front end onto the Obsidian application, so the application is required rather than
-- optional. Without it there is no vault registry to read, no notes to list, and nothing
-- for a chosen row to open, which is the same answer Convert and TmuxSessions give for a
-- tool with no sensible fallback, the root leaves the plugin unwired rather than opening
-- a picker onto silence.
--
-- The feature set is deliberately the core loop the Alfred and Raycast integrations kept
-- after years of their own pruning, search notes and open them, create a note from the
-- typed words, and hand a full text search to Obsidian itself. Everything else those
-- tools grew, OCR capture, workspace switching, media search, plugin folder shortcuts,
-- was filler by their own maintainers' account and none of it ships here.
-- The one bundle this plugin fronts, written once and read twice below, the tool
-- locator and the launcher row's own icon, so the two cannot drift apart.
local BUNDLE = "md.obsidian"

return {
  needs = {
    -- Lifting the notes opened through this tool to the front of the resting order.
    -- Optional, and without it the order by modification time simply stands. The glyph
    -- drawer turns the note emoji into a row icon sized to line up with every other
    -- list, and without it the rows simply carry no image.
    lib = {
      recency = { from = "recency", policy = "optional" },
      glyphIcon = { from = "glyphicon", policy = "optional" },
    },

    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the launcher row opens nothing, since show has no other way to reach " ..
                 "the shared stage" },
      -- The rescan runs a beat after the list opens rather than in front of it, so a
      -- landed rescan needs a way to repaint what is showing. Two words rather than one,
      -- the same composition FileSearch keeps, since the rows may be showing on the
      -- shared stage or hosted inside the launcher behind the ob alias, and each surface
      -- listens on its own word while ignoring the other's.
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a rescan landing after the list opened never reaches the screen, so " ..
                 "the list shows what the previous scan held until it is closed and " ..
                 "opened again" },
      redraw = { source = "root", policy = "optional",
        breaks = "a note list hosted inside the launcher stops updating when a rescan " ..
                 "lands, so it shows whatever the previous scan held for as long as the " ..
                 "scope stays open" },
      -- The shared fuzzy scorer is deliberately NOT declared here. It is not a published
      -- root value, declaring it as one earns an owed error on every load, and a surface
      -- declaring no matcher of its own already receives the shared strategy on opts as
      -- part of what declaring a surface earns. This plugin reads it there and uses it
      -- inside its own supplier, since the widget's own ranking pass is stood down.
    },

    tools = {
      -- The application every chosen note opens in, and the owner of the vault registry
      -- this plugin reads to find notes at all. The locator is the bundle id, and
      -- init.lua carries the same id as its one concretion, so a rename fails visibly
      -- in both places rather than silently in one.
      { name = "obsidian", kind = "app", locator = BUNDLE, policy = "required",
        reason = "the application every chosen note opens in, and the owner of the vault registry this plugin reads to find notes at all",
        origin = { cask = "obsidian" } },
    },
  },

  -- Both halves of what makes this tool reachable by typing its word, so ob and a space
  -- scopes the launcher to the same rows the standalone list shows.
  provides = {
    rows = "rows",
    select = "select",
  },

  -- No leader and no key, deliberately. This tool is reached by typing, the launcher row
  -- or the ob alias, which is rung two of the interaction ladder, and a chord would spend
  -- a scarce key on something a typed word already reaches. A rowed tool with no chord of
  -- its own is an established shape here rather than a first.
  defaults = {
    description = "Search Obsidian",
    glyph = "💎",
    aliases = { "ob", "obsidian" },
  },

  surface = {
    context = "obsidian",
    primary = { action = "insertSelected", description = "Open" },
    -- No extra bindings. Everything this plugin can do is an ordinary row you choose.
  },

  -- matcher is a real false. The rows are already filtered by this plugin's own word
  -- match and ordered by recency then modification time, and the trailing create and
  -- search rows carry the typed words in their titles, so a second uniform ranking pass
  -- would fight the order and could rank the action rows away entirely.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
    matcher = false,
  },

  registry = {
    -- bundle puts the real application icon on the launcher row in place of the drawn
    -- glyph, since a tool that fronts exactly one application reads fastest wearing that
    -- application's own face. The glyph in defaults stays as the fallback everywhere an
    -- app icon cannot go.
    row = { category = "Tools", detail = "search and open notes", bundle = BUNDLE,
      keywords = "obsidian notes vault markdown note write" },
    open = { member = "show", call = "dot" },
    scope = {
      -- False for the identical reason presentation.matcher above is, the rows arrive
      -- already filtered and ordered by this plugin's own supplier.
      matcher = false,
      rows = { member = "rows", call = "dot" },
      run = { member = "select", call = "dot" },
    },
  },
}
