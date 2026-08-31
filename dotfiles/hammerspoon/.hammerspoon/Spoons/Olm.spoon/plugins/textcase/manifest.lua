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

      -- The glance behind the launcher row's live subtitle, answering whether the covered
      -- app has a selection at all without reading it, three valued so the hint is shown
      -- only on an affirmative absence and never on a guess. Same module as read and apply,
      -- same dot discipline, and optional for the same reason, only the hint degrades, the
      -- row falling back to its ordinary subtitle.
      presence = { from = "paste", member = "selectionPresence", call = "dot", policy = "optional" },

      -- The shared lift to front ordering, the automatic per plugin grant keyed to this
      -- plugin's own settings slot, so the case a person last applied leads the list on the
      -- next open. No limit, the catalog is a fixed dozen. Optional, the list degrading to
      -- catalog order.
      recency = { from = "recency", policy = "optional" },
    },

    siblings = {
      -- Which application the launcher opened over, the same declaration menu search
      -- carries and for the same reason, the selection this plugin's launcher subtitle asks
      -- about belongs to that app and not to the chooser holding the keyboard. A closure
      -- reaching into the launcher only at call time, so no wiring edge, ordering false.
      -- Optional where menu search says required, since only the live subtitle asks, and
      -- without an answer the row simply keeps its static words.
      coveredApp = { plugin = "launcher", member = "coveredApp", call = "method",
        policy = "optional", ordering = false },
    },

    -- One root computed word, the trickle migration onto the shared stage. stagePresent is
    -- the hotkey door reached through registry.open's own kept fallback, VPN's identical
    -- precedent, since a launcher row choosing this tool pushes the registry's own
    -- presentation straight from root/compose.lua's rowIntercept and never calls show at
    -- all in the ordinary case. Optional, and it degrades to an inert press, never a crash,
    -- since a plugin asking before the stage's own configure has run is a wiring defect
    -- rather than a state a key press should silently swallow.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the special row dispatch reaches nothing, since show has no other way to " ..
                 "reach the shared stage" },
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
    primary = { action = "insertSelected", description = "Apply" },
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
            glyph = "🔠" },
    open = "show",
  },
}
