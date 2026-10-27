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
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Clipboard History",
    description = "Keep a history of what you copy and paste any of it back.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The row icons, named by the rows and drawn by Olm. The queued keycaps mark an appended row
  -- by its place in the batch, one to nine and then a shared mark. The thumbnails, the file type
  -- icons and the colour chip on a row are content and are drawn from the entry itself.
  icons = {
    url = { emoji = "🔗", sf = "link" },
    text = { emoji = "📝", sf = "doc.text" },
    queued1 = { emoji = "1️⃣", sf = "1.circle" },
    queued2 = { emoji = "2️⃣", sf = "2.circle" },
    queued3 = { emoji = "3️⃣", sf = "3.circle" },
    queued4 = { emoji = "4️⃣", sf = "4.circle" },
    queued5 = { emoji = "5️⃣", sf = "5.circle" },
    queued6 = { emoji = "6️⃣", sf = "6.circle" },
    queued7 = { emoji = "7️⃣", sf = "7.circle" },
    queued8 = { emoji = "8️⃣", sf = "8.circle" },
    queued9 = { emoji = "9️⃣", sf = "9.circle" },
    queuedMore = { emoji = "🔟", sf = "ellipsis.circle" },
    -- The manage history page.
    sweep = { emoji = "🧹", sf = "wind" },
    older = { emoji = "🕰️", sf = "clock.arrow.circlepath" },
    trim = { emoji = "✂️", sf = "scissors" },
    everything = { emoji = "🗑️", sf = "trash" },
    hint = { emoji = "⌨️", sf = "keyboard" },
    warn = { emoji = "⚠️", sf = "exclamationmark.triangle" },
    clipboard = { emoji = "📋", sf = "clipboard" },
    append = { emoji = "➕", sf = "plus" },
    delete = { emoji = "🗑️", sf = "trash" },
    back = { emoji = "⬅️", sf = "chevron.left" },
    pasteNext = { emoji = "⏩", sf = "forward" },
  },

  needs = {
    -- The engine every paste and every selection read runs through, the pasteboard
    -- snapshot, the restore, and the self capture guard all live there. Required,
    -- because without it there is no insertion mechanism left to fall back to, the
    -- whole manager is built on this one primitive rather than merely helped by it.
    --
    -- leader is optional, read by this plugin's own outer configure rather than by the
    -- manager below. It is Olm's view of every held leader, answering only whether one is
    -- down, so a provider that must wait for release waits for whichever leader its key sits
    -- on. Without it such a provider simply never waits. It stays a lib rather than the
    -- afterRelease descriptor field capture uses, because whether to wait is the chosen
    -- provider's answer at the moment of the press, and Raycast's is to fire while held.
    lib = {
      paste = { from = "paste", policy = "required" },
      leader = { from = "leader", policy = "optional" },
      -- Where the history, the frozen files, and the thumbnails live, lib/storage.lua's own
      -- durable root, so this plugin no longer names a directory under HOME of its own. It
      -- did for a long time, ~/.cache/hs-clipboard, which predated the storage lib and put
      -- the one store here that is genuinely durable under a cache name. Required, since a
      -- history with nowhere to go is not a clipboard manager.
      storage = { from = "storage", policy = "required" },
      -- The UI kit, which every piece of text in the preview pane is drawn through, so the pane
      -- names a role and never a font, a size, a line height or a colour. Required, since the
      -- pane has no drawing of its own left to fall back on.
      ui = { from = "ui", policy = "required" },
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
      -- Review finding H6, the costly one. deleteSelected, appendSelected, and every explicit
      -- re-render used to read a module local cache seeded only by the atom's own poll and
      -- never cleared on close, so a cold open plus an immediate d deleted whatever the
      -- previous session had highlighted, wherever it now sat in history, an unrecoverable
      -- wrong deletion. This word reads the shared widget directly instead.
      stageSelectedItem = { source = "root", policy = "optional",
        breaks = "the preview, append, and delete all act on whatever the previous session " ..
                 "last highlighted rather than the row actually under the cursor, since none " ..
                 "of them has any other way to ask the shared widget directly" },
    },
  },

  -- What this plugin can run beyond opening its list, three actions on the manager, append copy,
  -- paste next and the manage history page. They were registry commands until phase 2b of the
  -- keymap plan, and they are action descriptors now, init.lua's actions, so Olm binds the keys
  -- below to them and lists each as a launcher row beside this tool's own. The manager is not
  -- itself scoped by an alias.
  provides = {
    actions = "actions",
  },

  -- Hyper plus X opens the native manager. No icon and no aliases are stated for this
  -- tool, here or in config/keymap.lua, unlike most of the other pickers. Append copy and paste next sit on global combinations, Control and Option
  -- with C and V, rather than on a Hyper chord, because both act on whatever was frontmost a
  -- moment ago rather than on a list that is already open, a different gesture that wants a
  -- plain combination, and it is the only place either has ever lived. leader false is how a
  -- row says it sits on no leader. Manage history has no key on purpose. It already has one
  -- inside the picker, and a second global chord for a door one keystroke from the list it acts
  -- on would be a key to remember for nothing, so its launcher row is how it is found.
  defaults = {
    leader = "app",
    description = "Clipboard history",
    bindings = {
      { action = "open", key = "X" },
      { action = "appendCopy", key = "C", mods = { "ctrl", "alt" }, leader = false },
      { action = "pasteNext", key = "V", mods = { "ctrl", "alt" }, leader = false },
    },
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
      { key = "a", action = "appendSelected", description = "Append to batch", icon = "append",
        when = "clipboardHistoryList" },
      { key = "d", action = "deleteSelected", description = "Delete", icon = "delete",
        when = "clipboardHistoryList" },
      -- The manage history page, where history is deleted by age rather than a row at a time.
      -- The same key steps back off the page, since that is what a person presses again.
      { key = "m", action = "manageHistory", description = "Manage history", icon = "sweep" },
      -- A listing rather than a binding. Backspace on an empty field belongs to the Chooser
      -- atom, which reads it directly as its `back` hook, so there is nothing here to bind and
      -- chord = false says so. It is still declared, because the key panel is where a key
      -- becomes visible and a way out nobody can see is a way out nobody takes, and it is gated
      -- so it appears exactly while there is a page to leave.
      { key = "delete", action = "leaveManageHistory", when = "clipboardManagingHistory",
        chord = false, description = "Back to history", icon = "back" },
    },
    -- No matcher. Until phase three of the unified search on 2026-10-17 this declared the words
    -- strategy, injected for buildChoices to score the free text itself, since entries are prose
    -- and code searched from the inside and fuzzy then cost too much over long bodies. The shared
    -- search now matches a long body by a word start or inside a word over a lowered copy it
    -- keeps, so the clipboard ranks through it like every list, decisions/olm-unified-search.md.
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
  -- No matcher, so the shared search ranks the history, phase three of
  -- docs/PLAN-UNIFIED-SEARCH.md on 2026-10-17. Until then this declared matcher false, since
  -- buildChoices did all of its own filtering, the type prefix parsed off the query and the free
  -- text scored by the words matcher while keeping the store's recency order. A row now declares
  -- its title, its body and paths as names and its place in the store as a bonus, and searchText
  -- answers what follows the type prefix, which buildChoices still reads to narrow by kind. The
  -- manage history page reads the same field as a duration, and searchText answers nothing there,
  -- so its rows keep their order whatever is typed, the one thing matcher false still did.
  --
  -- intercept and back are the manage history page's own drill down pair, unchanged in what
  -- they do, migrated in how they reach the field, cfg.stageSetQuery and cfg.stageSetPlaceholder
  -- replacing the direct picker calls this used to make on an instance it held itself.
  --
  -- Contract v3, docs/BRIEF-CONTRACT-V3.md, was weighed against this pair and left both fields
  -- exactly as they are, for two different reasons rather than one. A child is pushed only from
  -- select answering a table for a row that was just chosen, the one door host/stage's own
  -- intercept chain opens, on Return, insertSelected, or a click, and no other door exists, no
  -- published root word hands a plugin the stage's own push directly the way stagePresent and
  -- stagePop already do. The prune page's own delete rows keep intercept for the reason contract
  -- v3 names outright, decision three, a row that mutates the list it is standing on rather than
  -- moving to a new one, exactly the case that pair is reserved for. The page switch itself,
  -- entering and leaving manage history, was weighed the same way and earns the identical
  -- reservation for a different reason. It is reached by the Hyper m binding and by its own
  -- keyless launcher command, both acting on whatever list already happens to be open rather
  -- than completing a highlighted row, so there is no select call for a child ever to be
  -- returned from. displayprofiles and browsertabs, contract v3's own two converted plugins,
  -- drill into every one of their levels by choosing a row, the shape neither of this plugin's
  -- two pages shares, so intercept and back, already migrated onto the published stage words
  -- above, stay the whole of how this plugin's two pages open and close.
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
    searchText = { member = "manager.searchText", call = "dot" },
    -- The most history rows shown, cut after ranking, decided 2026-10-17, so the provider styles
    -- two hundred of a thousand entries on a keystroke and an empty field shows the newest two
    -- hundred. The supplier still hands every entry over, from a row cache, so the cut never
    -- decides which entries can be found.
    rowLimit = 200,
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
  -- call convention beyond the default.
  registry = {
    row = { category = "Clipboard", icon = "clipboard" },
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
  },
}
