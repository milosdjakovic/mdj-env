-- MenuSearch, what it declares about itself.
--
-- Pure composition root policy over the shared Chooser atom and the Accessibility
-- api hs.application already exposes, so it names no external tool and has no
-- dependencies file. There is no needs table here at all, since a present field is a
-- claim and this plugin has nothing to claim.
--
-- Two of its real collaborators still have nowhere to go here. configure also reads
-- coveredApp, a function answering which app the launcher currently covers, and
-- refreshLauncher, a function poking the launcher when this plugin's async menu fetch
-- lands. Both come from the Launcher host rather than from a sibling plugin, from
-- Olm's own lib, or from plain root computed data. needs.siblings can only name a
-- plugin under plugins, needs.lib can only name a module under lib, and needs.data
-- describes a value the plugin cannot derive rather than a live capability of a
-- concrete other module that must exist and be wired first. None of the three fits a
-- dependency on a host, so this stays undeclared rather than forced into a field that
-- would misdescribe it, the same gap the audit named and not one this manifest can
-- close on its own.
return {
  -- The registry and every sibling lookup know this plugin as menuSearch, camel
  -- cased, while the directory beside this file is menusearch, lowercase.
  name = "menuSearch",

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
