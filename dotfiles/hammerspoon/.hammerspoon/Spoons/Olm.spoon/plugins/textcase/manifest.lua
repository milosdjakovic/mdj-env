-- TextCase, what it declares about itself.
--
-- The interesting one of the prototype three, because it is the plugin whose whole reason
-- for working depends on two mechanisms it does not own. Both are declared and injected,
-- so this plugin still names no clipboard.

-- The registry and every sibling lookup know this plugin as textCase, camel cased, while
-- the directory beside this file is textcase, lowercase.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Text Case",
    description = "Change the case of the selected text, previewed before it is pasted back.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The icons this plugin names, in the emoji set and the SF Symbol set. The one named for the
  -- plugin is its identity icon, which the launcher row and the scoped list both wear.
  -- Each case row names the icon keyed by its transform id, so a case added to
  -- transforms.lua declares its icon here under the same id.
  icons = {
    -- The primary, Apply, and the secondary, Copy, in the action panel. Each names what the verb
    -- does, never the key that runs it, since the panel already prints the chord beside it.
    apply = { emoji = "✅", sf = "checkmark.circle" },
    copy = { emoji = "📋", sf = "doc.on.doc" },
    textcase = { emoji = "🔠", sf = "textformat" },
    -- The guidance row shown when nothing is selected.
    none = { emoji = "🚫", sf = "nosign" },
    upper = { emoji = "🔠", sf = "characters.uppercase" },
    lower = { emoji = "🔡", sf = "characters.lowercase" },
    title = { emoji = "🔤", sf = "textformat.size" },
    sentence = { emoji = "✍️", sf = "text.alignleft" },
    capitalize = { emoji = "🔤", sf = "textformat.abc" },
    toggle = { emoji = "🔁", sf = "arrow.up.arrow.down" },
    camel = { emoji = "🐫", sf = "curlybraces" },
    pascal = { emoji = "🔺", sf = "curlybraces.square" },
    snake = { emoji = "🐍", sf = "underline" },
    constant = { emoji = "📢", sf = "megaphone" },
    kebab = { emoji = "🍢", sf = "minus" },
    dot = { emoji = "🔵", sf = "ellipsis" },
  },

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

      -- The glance behind the launcher row's live subtitle, answering whether the covered
      -- app has a selection at all without reading it, three valued so the hint is shown
      -- only on an affirmative absence and never on a guess. Same module as read and apply,
      -- same dot discipline, and optional for the same reason, only the hint degrades, the
      -- row falling back to its ordinary subtitle.
      presence = { from = "paste", member = "selectionPresence", call = "dot", policy = "optional" },

      -- The covered app's selected text read through accessibility, which the launcher scope
      -- previews from, since a scope lists while the launcher holds the keyboard and a Cmd+C
      -- read cannot run then. Optional, the scope previewing a sample phrase without it.
      peek = { from = "paste", member = "selectedTextOf", call = "dot", policy = "optional" },

      -- The shared lift to front ordering, the automatic per plugin grant keyed to this
      -- plugin's own settings slot, so the case a person last applied leads the list on the
      -- next open. No limit, the catalog is a fixed dozen. Optional, the list degrading to
      -- catalog order.
      recency = { from = "recency", policy = "optional" },
    },

    -- Root computed words. stagePresent, from the trickle migration onto the shared stage, is
    -- the hotkey door reached through registry.open's own kept fallback, VPN's identical
    -- precedent, since a launcher row choosing this tool pushes the registry's own
    -- presentation straight from root/compose.lua's rowIntercept and never calls show at
    -- all in the ordinary case. Optional, and it degrades to an inert press, never a crash,
    -- since a plugin asking before the stage's own configure has run is a wiring defect
    -- rather than a state a key press should silently swallow.
    data = {
      stageSelectedItem = { source = "root", policy = "optional",
        breaks = "Copy finds no case to copy and does nothing" },
      stageHide = { source = "root", policy = "optional",
        breaks = "Copy leaves the list open after copying" },
      stagePresent = { source = "root", policy = "optional",
        breaks = "the special row dispatch reaches nothing, since show has no other way to " ..
                 "reach the shared stage" },
      -- Which application the launcher opened over, the same word menu search declares and for
      -- the same reason, the selection this plugin's launcher subtitle asks about belongs to
      -- that app and not to the chooser holding the keyboard. A root published closure over
      -- the launcher since phase three of the core split, so this plugin names no host.
      -- Optional where menu search says required, since only the live subtitle asks.
      coveredApp = { source = "root", policy = "optional",
        breaks = "the launcher row keeps its static subtitle rather than saying whether a selection is there to recase" },
    },
  },

  -- What puts this tool in the launcher's scope set, so its alias and a space lists every case.
  -- The scope previews the covered app's selection read through accessibility, and where the
  -- app does not expose one it previews a sample and the pick reads the selection itself. The
  -- scope was once removed for having only the sample, AGENTS.md has the trail.
  provides = {
    rows = "scopeRows",
    select = "scopeRun",
  },

  -- Opened from the launcher only, so it proposes no key at all. A default of nothing is
  -- still a default, and it is why the file says so rather than leaving the field out.
  defaults = {
    description = "Text Case",
    icon = "textcase",
    launcherRow = true,
    aliases = { "tc", "case" },
    example = "Try tc to recase the selection",
  },

  surface = {
    context = "textCase",
    primary = { action = "insertSelected", description = "Apply", icon = "apply" },
    -- Command and Return copies the case rather than pasting it, docs/PLAN-ACTION-PANEL.md.
    secondary = { action = "copySelected", description = "Copy", icon = "copy" },
  },

  -- The presentation contract, contract v2, docs/BRIEF-CONTRACT-V2.md. rows and select are
  -- this plugin's own colon methods, so every field below says call = method, stated
  -- outright, never the bare string shorthand this contract allows everywhere else a
  -- member is not a presentation's own. No matcher, so this presentation inherits the
  -- root default, fuzzy, the one picker in the whole tree that deliberately keeps it,
  -- stated as such at obj:rows above. No paneWidth, this list reserves no companion pane.
  --
  -- enter is contract v2's own second addition and the reason this plugin needed it before
  -- the word for it existed. obj:enter reads the selection and proceeds once the rows built
  -- from it are ready, so the picker never appears before its first row means anything, the
  -- identical rule this file's own retired show already followed inline.
  presentation = {
    rows = { member = "rows", call = "method" },
    select = { member = "select", call = "method" },
    enter = { member = "enter", call = "method" },
  },

  -- show is a colon method, obj:show(), so open takes the default call. surface is no
  -- longer declared, host/stage's own surfaceFor(identity) answering the five generic nav
  -- verbs now that presentation above exists, and this plugin binds no verb beyond them.
  registry = {
    -- detail is the one member spec detail in the tree rather than a plain string, resolved
    -- lazily by the registrar exactly as open is. The launcher asks it per open, through a
    -- per keystroke read the plugin caches per open id, so the row can say up front that
    -- nothing is selected, the answer a person otherwise only learns after opening a tool
    -- whose whole point is the selection. The plugin answers the ordinary words, recase the
    -- selection in place, whenever it cannot tell, so the row never nags on a guess.
    row = { category = "Text", detail = { member = "launcherDetail", call = "method" },
            icon = "textcase",
            keywords = "uppercase, lowercase, camel case, snake case, kebab case, capitalize" },
    open = "show",
    -- verbs are what the action panel offers over a scope row, keyed by the surface actions
    -- above, so the scoped list offers Apply and Copy as the tool's own list does.
    scope = {
      rows = { member = "scopeRows", call = "method" },
      run = { member = "scopeRun", call = "method" },
      verbs = {
        insertSelected = { member = "scopeRun", call = "method", closes = true },
        copySelected = { member = "scopeCopy", call = "method", closes = true },
      },
    },
  },
}
