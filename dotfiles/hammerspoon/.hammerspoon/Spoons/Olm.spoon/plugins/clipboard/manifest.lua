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
      { name = "ffmpeg", kind = "path", policy = "optional", unit = "preview",
        reason = "video clipboard previews",
        origin = { brew = "ffmpeg" } },
      { name = "ffprobe", kind = "path", policy = "optional", unit = "preview",
        reason = "reading a video duration so a preview frame is picked mid clip",
        origin = { brew = "ffmpeg" } },
      -- Both of these were run by absolute path and declared nowhere, so the layer that
      -- guarantees a tool is present had never heard of either, and a preview that quietly
      -- stopped rendering would have had nothing to say about why.
      { name = "sips", kind = "system", locator = "/usr/bin/sips", policy = "optional",
        unit = "preview",
        reason = "resizing a raster image to a preview box and forcing it to png, which is " ..
                 "what makes a heic or a webp render in the preview at all",
        origin = { macos = "ships with the system" } },
      { name = "head", kind = "system", locator = "/usr/bin/head", policy = "optional",
        unit = "ui",
        reason = "reading the front of a text file off the main thread, so previewing a " ..
                 "large one cannot freeze the pane",
        origin = { macos = "ships with the system" } },
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

      -- Five root computed words, the trickle migration onto the shared stage. stagePresent
      -- is the hotkey door, reached through providers/hammerspoon.lua's own toggle rather than
      -- called directly, and the launcher row's own manageHistory command when nothing is
      -- showing. redrawPresented is the async seam every explicit redraw in this file now
      -- asks for, once this presentation, and no other, is what the stage is actually showing.
      -- stageHide is what providers/hammerspoon.lua's own toggle closes the window with.
      -- stageSetQuery and stageSetPlaceholder are this plugin's own addition to the published
      -- set, the direct field control the manage history page needs to change both what the
      -- field says and what it holds without the presentation closing, since a static
      -- presentation.placeholder cannot express a page that changes what the box means.
      stagePresent = { source = "root", policy = "optional",
        breaks = "the history picker opens nothing, whichever door asked, since UI.show has " ..
                 "no other way to reach the shared stage" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a right click delete, a media preview finishing, and every other answer " ..
                 "landing after the keystroke that asked for it never reaches the screen " ..
                 "while this presentation, and no other, is what is actually showing" },
      stageHide = { source = "root", policy = "optional",
        breaks = "a second Hyper plus X, or an external toggle, can no longer close the " ..
                 "history picker, since providers/hammerspoon.lua's own toggle has no other " ..
                 "way to ask the shared stage to hide" },
      stageSetQuery = { source = "root", policy = "optional",
        breaks = "entering and leaving the manage history page stops clearing the field, so " ..
                 "whatever was typed as a search is read as a duration or the other way round" },
      stageSetPlaceholder = { source = "root", policy = "optional",
        breaks = "the field keeps reading Search clipboard on the manage history page, and " ..
                 "the reverse on the way back, since intercept and back have no other way to " ..
                 "put the level's own wording in the field" },
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
      -- Both act on one highlighted entry, so both are gated on the list being the history
      -- rather than the manage history page. Inert would have been enough for the keys, and is
      -- not enough for the panel, since a key listed there while it does nothing is exactly the
      -- disagreement between a hint and a binding the two discoverability mandates exist to
      -- prevent. Gated, they leave the panel the moment the page opens and come back with it.
      { key = "a", action = "appendSelected", description = "Append to batch", glyph = "➕",
        when = "clipboardHistoryList" },
      { key = "d", action = "deleteSelected", description = "Delete", glyph = "🗑️",
        when = "clipboardHistoryList" },
      -- The manage history page, where history is deleted by age rather than a row at a time.
      -- The same key steps back off the page, since that is what a person presses again.
      { key = "m", action = "manageHistory", description = "Manage history", glyph = "🧹" },
      -- A listing rather than a binding. Backspace on an empty field belongs to the Chooser
      -- atom, which reads it directly as its `back` hook, so there is nothing here to bind and
      -- chord = false says so. It is still declared, because the hint panel is where a key
      -- becomes visible and a way out nobody can see is a way out nobody takes, and it is gated
      -- so it appears exactly while there is a page to leave.
      { key = "delete", action = "leaveManageHistory", when = "clipboardManagingHistory",
        chord = false, description = "Back to history", glyph = "⬅️" },
    },
    -- Entries here are prose and code searched from the inside, a real remembered
    -- word rather than an abbreviation of a short label, so the words matcher fits
    -- and fuzzy would only cost more for less. The manager still opts its own picker
    -- out of the atom's own ranking, since it parses a type prefix off the query
    -- itself, but it wants the shared matching value handed to it anyway to score
    -- the free text part, which is what makes the pane worth having. Migrated onto
    -- the shared stage, contract v2, the opt out itself now travels through
    -- presentation.matcher below as false, while this word stays declared here too,
    -- unread by the stage, since needs.data's own engine facing matcher injection,
    -- unrelated to either, still reads this exact word for buildChoices's own scoring.
    matcher = "words",
    -- The docked companion pane is most of what this picker is, the live preview of
    -- whatever is highlighted, so it earns the reserved room rather than going without.
    pane = true,
  },

  -- The presentation contract, contract v2, docs/BRIEF-CONTRACT-V2.md. rows and select are
  -- manager.rows and manager.select, forwarded straight through to the ui submodule's own
  -- buildChoices and onSelect, the same shape every other presenting plugin's own rows and
  -- select already take. placeholder resolves once, at register, to the history wording,
  -- ui.placeholder below, the manage history page's own wording reached live instead through
  -- cfg.stageSetPlaceholder, since a static contract field cannot express a page that changes
  -- what the field means.
  --
  -- matcher is false, contract v2's own first addition and the largest reason this plugin
  -- needed it. The atom's own scoring did no filtering here before the migration, buildChoices
  -- owning every bit of it itself, the type prefix parsed off the query and the free text part
  -- scored by the injected words matcher while preserving the store's own recency order, and
  -- the manage history page reads the same field as a duration with no relationship to entry
  -- content at all. host/stage writes false onto the live instance before every show and swap,
  -- so both pages keep exactly the filtering, or the total absence of it, they always had.
  --
  -- intercept and back are the manage history page's own drill down pair, unchanged in what
  -- they do, migrated in how they reach the field, cfg.stageSetQuery and cfg.stageSetPlaceholder
  -- replacing the direct picker calls this used to make on an instance it held itself.
  --
  -- onHighlight, onScroll, onRightClick, onPositioned, and onClose carry the live preview, its
  -- scroll, its right click delete, its dock, and its teardown, the identical shape filesearch
  -- and processes already keep, minus the anchor arithmetic and the cfg.onPositioned call
  -- host/stage now owns for every presenting plugin. onScroll and onRightClick are contract
  -- v2's own third and fourth additions, found by this migration rather than named by either
  -- brief, since a canvas companion has no scroll callback of its own and a canvas row has no
  -- native right click handling either.
  presentation = {
    rows = { member = "manager.rows", call = "dot" },
    select = { member = "manager.select", call = "dot" },
    placeholder = { member = "manager.placeholder", call = "dot" },
    onPresent = { member = "manager.onPresent", call = "dot" },
    intercept = { member = "manager.intercept", call = "dot" },
    back = { member = "manager.back", call = "dot" },
    onHighlight = { member = "manager.onHighlight", call = "dot" },
    onScroll = { member = "manager.onScroll", call = "dot" },
    onRightClick = { member = "manager.onRightClick", call = "dot" },
    onPositioned = { member = "manager.onPositioned", call = "dot" },
    onClose = { member = "manager.onClose", call = "dot" },
    -- true inherits the chooser's own width, matching cfg.previewW = true unconditionally,
    -- the manager's own config, this plugin's only real layout override even before the
    -- migration, consumer map surprise 9.4 naming the other eight as restated atom defaults.
    paneWidth = true,
    matcher = false,
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
    -- open still stays, and still matters, the hotkey door this plugin's own leader key binds
    -- to, unchanged by the migration since it never called the picker directly. It resolves
    -- the provider chain, native or an external manager, and only the native leg's own
    -- manager.show now reaches cfg.stagePresent underneath, so an external provider is
    -- entirely untouched by any of this.
    open = "open",
    -- surface = "manager" stays declared, a narrower exception to PLUGIN-CONTRACT.md's own "a
    -- presenting plugin declares no registry.surface" rule that Processes' own migration
    -- already carved out. isShowing, selectNext, selectPrev, insertSelected, and hide are
    -- gone, host/stage's own surfaceFor(identity) answering all five now, but appendSelected,
    -- deleteSelected, manageHistory, leaveManageHistory, scrollPreviewDown, and
    -- scrollPreviewUp, the extra verbs surface.extra above binds keys to, live on nowhere
    -- else, and root/compose.lua's own surfaceAdapterFor falls through to whatever this field
    -- names once the stage's own five have answered nothing. manager.isShowing and
    -- manager.hide also stay real functions rather than being deleted with the other three,
    -- since providers/hammerspoon.lua's own toggle calls them directly, a caller the nav
    -- system's own five never was.
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
      -- The manage history page from the launcher, for the case where the picker is not open and
      -- deleting a slice of history is the whole errand. No key and no shortcut, deliberately.
      -- It already has one inside the picker, and a second global chord for a door that is one
      -- keystroke away from the list it acts on would be a key to remember for nothing. The row
      -- is how it is found, which is what a keyless command is for.
      manageHistory = {
        fn = { member = "manager.manageHistory", call = "dot" },
        row = { category = "Clipboard", glyph = "🧹",
          description = "Manage clipboard history",
          keywords = "clipboard delete clear wipe prune history age old hour day week" },
      },
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
