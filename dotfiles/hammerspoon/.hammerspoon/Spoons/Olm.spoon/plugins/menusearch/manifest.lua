-- MenuSearch, what it declares about itself.
--
-- Pure composition root policy over the shared Chooser atom and the Accessibility
-- api hs.application already exposes, so it names no external tool and has no
-- dependencies file. There is no needs table here at all, since a present field is a
-- claim and this plugin has nothing to claim.
--
-- Its two real collaborators are declared, and the note that used to sit here saying they
-- could not be is wrong. It claimed needs.siblings can only name a plugin under plugins, and
-- hosts and plugins share ONE identity keyed set, so naming the launcher works exactly as
-- naming a plugin does. Believing otherwise left both undeclared, so nothing delivered them,
-- and asking this plugin for rows raised on a nil coveredApp the moment its word was typed.
--
-- Both are ordering false. Each arrives as a closure called when a person types rather than
-- while anything is being wired, and this plugin is deliberately configured BEFORE the
-- launcher, so an eager edge would invert that order for no reason.
return {
  -- The registry and every sibling lookup know this plugin as menuSearch, camel
  -- cased, while the directory beside this file is menusearch, lowercase.
  name = "menuSearch",

  needs = {
    siblings = {
      -- Which application the launcher opened over, which is the whole subject of this
      -- plugin, since the menus it searches belong to that app and not to the launcher.
      coveredApp = { plugin = "launcher", member = "coveredApp", call = "method",
        policy = "required", ordering = false },
      -- Poking the launcher to draw again once this plugin's own menu read lands, the same
      -- late answer shape the browser tab and relay lists take.
      refreshLauncher = { plugin = "launcher", member = "refresh", call = "method",
        policy = "optional", ordering = false },
    },
  },

  -- Scoped by the launcher, the alias lists the frontmost app's menus the same way
  -- the picker does and choosing one runs the same item. It is a discovery opener,
  -- so it has no launcher row of its own, the aliases are found in the alias
  -- directory instead.
  provides = {
    rows = "rows",
    select = "select",
  },

  defaults = {
    leader = "app",
    key = "e",
    description = "Menu search",
    glyph = "📋",
    aliases = { "m", "menu" },
  },

  surface = {
    context = "menuSearch",
    -- This plugin's configure reads the docked panel's three callbacks nested under one
    -- field rather than as three flat ones, so the shape is named here. Four plugins
    -- disagree about this and the disagreement lives in their own configure contracts,
    -- so it has to be declared. Assuming the flat form silently removed the panel from
    -- every one of them while handing each three fields it never reads.
    panelAs = "panel",
    primary = { action = "insertSelected", description = "Run" },
  },

  -- open, surface, scopeRows and scopeRun are all assigned as plain closures inside this
  -- plugin's own configure, self.open, self.surface, self.scopeRows, self.scopeRun, so none
  -- of them expects a receiver, and every one below says dot rather than taking the default.
  -- No row, since this tool is a discovery opener reached through the alias directory rather
  -- than a launcher row of its own, matching the retired root's own registration exactly.
  registry = {
    open = { member = "open", call = "dot" },
    surface = "surface",
    shortcut = "leader",
    scope = {
      rows = { member = "scopeRows", call = "dot" },
      run = { member = "scopeRun", call = "dot" },
    },
  },
}
