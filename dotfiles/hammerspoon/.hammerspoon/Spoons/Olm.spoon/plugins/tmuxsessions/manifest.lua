-- TmuxSessions, what it declares about itself.
--
-- Written when this plugin arrived on main while the manifest layer was being built, so it
-- is the first one authored against the finished contract rather than migrated onto it. That
-- makes it the honest test of whether the contract holds, and it does. Everything the retired
-- root spelled out for this tool, twelve providers and options and a registration of its own,
-- is either declared below or has moved inside the plugin where it belongs.
--
-- Two things did move inside rather than being declared. The provider chain and its order now
-- fall back to this plugin's own default, since a fresh install must list sessions with nobody
-- having named a terminal, and the one path the CLI based backends need is resolved by this
-- plugin out of the dependency scope it already receives. Both were root knowledge in the
-- retired file, and both would have meant editing the root to add a provider.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Tmux Sessions",
    description = "Jump to any tmux window across every session.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The directory is tmuxsessions, one word, while the identity everywhere outside this
  -- folder, the registry, the launcher row, the Hyper context, is tmuxSessions.
  name = "tmuxSessions",

  -- The row icons, named by the rows and drawn by Olm.
  icons = {
    active = { emoji = "🟢", sf = "circle.fill" },  -- the window currently on screen
    window = { emoji = "🪟", sf = "macwindow" },
    terminal = { emoji = "💻", sf = "apple.terminal" },
    tmuxsessions = { emoji = "🗂️", sf = "terminal" },
  },

  needs = {
    -- Lifting the last session or window you jumped to. Keyed by the tmux target a row and a
    -- jump both use, session and index, so a killed window leaves a key nothing can produce
    -- again. Optional, and without it the resting order simply stands.
    lib = {
      recency = { from = "recency", policy = "optional" },
    },

    -- One root computed word, the trickle migration onto the shared stage. stagePresent is
    -- the hotkey door this plugin's own show reaches for, the plugin root still delegating
    -- to the chooser submodule exactly as it always did. Optional, degrading to an inert
    -- press rather than a crash, since a plugin asking before the stage's own configure has
    -- run is a wiring defect rather than a state a key press should silently swallow.
    data = {
      stagePresent = { source = "root", policy = "optional",
        breaks = "the leader key opens nothing, since show has no other way to reach the " ..
                 "shared stage" },
    },

    tools = {
      -- Required, and it is the one dependency in this plugin that genuinely is. This tool is
      -- a front end onto the tmux server and nothing else, so an absent tmux leaves nothing to
      -- list and nothing to switch. Declaring it required is what makes Olm leave the whole
      -- plugin unwired rather than open a picker onto silence, which is the same answer
      -- Convert and Eyedropper already take for a tool with no sensible fallback.
      { name = "tmux", kind = "path", policy = "required", unit = "engine",
        reason = "querying and switching every session and window, the whole reason this tool exists",
        origin = { brew = "tmux" } },
      -- Alacritty and WezTerm carry no AppleScript dictionary, so a fresh attach goes through
      -- each one's own command line form, reached through open, the one door from Hammerspoon
      -- to a bundle's own argv. Optional, since a missing path dims those two backends among
      -- the Terminal choices and leaves the three that script themselves working. The retired
      -- generated file carried this as two lines, one per terminal, since each backend file
      -- declared open for itself. Merged into the one line above, it has no single owner left
      -- to name, so it carries no unit rather than crediting only one of the two terminals it
      -- actually serves.
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional",
        reason = "launching Alacritty or WezTerm already attached to a session",
        origin = { macos = "ships with the system" } },
    },
  },

  -- Both halves of what makes a tool reachable by typing its word, so the launcher's own set
  -- question finds this plugin without naming it.
  provides = {
    rows = "rows",
    select = "select",
  },

  -- U reads as the key nothing else wanted, and Tmux Manager rather than Tmux Sessions
  -- because the picker reaches windows and the terminal they attach in as well as sessions.
  defaults = {
    leader = "app",
    -- The open key, a bindings row whose action is open, on the leader above.
    bindings = { { action = "open", key = "U" } },
    description = "Tmux Manager",
    icon = "tmuxsessions",
    aliases = { "u", "tmux" },
  },

  surface = {
    context = "tmuxSessions",
    -- insertSelected rather than the retired enter, the atom's own real completion path,
    -- which host/stage's own surfaceFor answers directly.
    primary = { action = "insertSelected", description = "Select" },
    -- Which terminal a fresh attach opens into, a verb of the action panel alone with choices,
    -- docs/PLAN-ACTION-PANEL.md. It replaced a settings level behind the list's last row on
    -- 2026-10-30. terminalChoices and setTerminal are colon methods on the chooser submodule,
    -- which registry.surface below names.
    extra = {
      { action = "setTerminal", description = "Terminal", icon = "terminal", choices = "terminalChoices" },
    },
  },

  -- The presentation contract, contract v3, docs/BRIEF-CONTRACT-V3.md. rows and select are
  -- this plugin's own chooser.rows and chooser.select, plain closures assigned inside the
  -- chooser submodule exactly the way its show, placeholder, and every other public member
  -- already are, so every field below says call = dot, stated outright, never the bare
  -- string shorthand this contract allows everywhere else a member is not a presentation's
  -- own. placeholder resolves once, at register, to the top level's own static wording, the
  -- settings child built when its row is chosen carrying its own instead, a plain field on
  -- a table built at runtime rather than something the registrar ever resolves. onPresent
  -- carries the fresh read and the recency prune M.show used to do inline before this
  -- plugin had a presentation to defer through instead, run on both doors, present and push
  -- alike. No intercept and no back at this level any more. The top level itself never
  -- mutated a list it stood on or left anywhere by itself, that was always the settings
  -- level's own business, so choosing Settings now answers a child presentation from select
  -- instead, and that child carries its own intercept directly rather than through a
  -- manifest member, host/stage's own Stage:pop already restoring this level on Backspace
  -- with no back hook needed from either level.
  --
  -- No matcher is declared, so the shared search filters the windows and the Settings door
  -- alike. The windows arrive ordered by what was jumped to last, which is the order of an
  -- empty query.
  presentation = {
    rows = { member = "chooser.rows", call = "dot" },
    select = { member = "chooser.select", call = "dot" },
    placeholder = { member = "chooser.placeholder", call = "dot" },
    onPresent = { member = "chooser.onPresent", call = "dot" },
  },

  -- configure alone leaves this plugin with an engine and no picker. The picker lives on the
  -- chooser submodule, which needs its own configure and its own start before a session can
  -- show, and both are plain dot called functions there rather than methods, so each says so.
  --
  -- The engine is a target for the same reason the chooser is, and adding it is what stopped a
  -- granted service being able to go missing here. A declared step receives the whole granted
  -- options table, so the engine reads deps and recency straight off it, and the plugin's own
  -- configure no longer writes a list of ambient fields it has to keep in step with whatever
  -- its needs block declares. It was exactly such a list, restating two fields and forgetting a
  -- third, that left this picker with no remembered order at all and nothing anywhere saying
  -- so. Its configure is a colon method, so it takes the default call rather than naming one.
  --
  -- Both callers of the engine's configure are partial and neither knows the other's fields,
  -- which is the arrangement the chooser already had and which the engine's own configure was
  -- changed to allow, writing only what it was actually handed rather than resetting itself.
  wiring = {
    { target = "engine", method = "configure" },
    { target = "chooser", method = "configure", call = "dot" },
    { target = "chooser", method = "start", call = "dot" },
  },

  -- show is a colon method on this plugin's own root, so open takes the default call.
  -- hostRows and activate both live on the chooser submodule as plain dot called functions,
  -- reached only by the scope below, never by the nav registry.
  --
  -- No detail on the row, matching fileSearch rather than displayProfiles, because this tool
  -- has a real chord and its subtitle should read like every other keyed tool's, the category
  -- then the combination, with the alias hint appended by the catalogue itself.
  --
  -- surface names the chooser submodule, where the Terminal verb's two methods live.
  -- host/stage's own surfaceFor still answers the five generic nav verbs, and the root falls
  -- through to this submodule for any verb beyond them.
  registry = {
    row = { category = "Tools",
      keywords = "sessions, terminal, ghostty" },
    open = "show",
    surface = "chooser",
    hosted = true,
    shortcut = "leader",
    scope = {
      -- Both names are reached THROUGH the chooser submodule, which is where this plugin
      -- keeps its picker, the same path browserTabs and fileSearch already write. A bare
      -- name is walked against this plugin's own root, finds nothing there, and answers nil
      -- in silence, which is what the first version of this manifest did. The scope was
      -- still built, still registered and still resolvable, so typing the word opened onto
      -- an empty list rather than failing anywhere a person could see it.
      rows = { member = "chooser.scopeRows", call = "dot" },
      run = { member = "chooser.activate", call = "dot" },
    },
  },
}
