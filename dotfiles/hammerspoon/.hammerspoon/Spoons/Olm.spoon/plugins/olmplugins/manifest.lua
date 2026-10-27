-- Olm Plugins, what it declares about itself.
--
-- A friendly front end onto the one plugin switch, lib/pluginswitch.lua. It owns no data of its
-- own, it only reads the catalog and stages choices through the root words below, so the switch
-- stays the one place that ever writes which plugins are off.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Olm Plugins",
    description = "Switch Olm plugins on or off, applied with one reload.",
    author = "Milos Djakovic",
    version = "0.2",
    license = "MIT",
  },

  -- The row icons. A plugin row carries only a circle, never a checkmark, the one marker
  -- convention this codebase uses for which state is current. Green is on and red is off.
  icons = {
    plugins = { emoji = "🧩", sf = "puzzlepiece.extension" },
    apply = { emoji = "🔄", sf = "arrow.clockwise" },
    selected = { emoji = "🟢", sf = "circle.fill" },
    notSelected = { emoji = "🔴", sf = "circle" },
  },

  needs = {
    -- No lib. The kit the pane draws through arrives with the docked pane, which hands it to the
    -- describer on every paint, so nothing here reads opts.ui.
    data = {
      -- The page's words over the one switch, published by the root over lib/pluginswitch.lua.
      -- The catalog lists the plugins under plugins with their about block, needs and what
      -- applying the staged set would leave, the cascade answers what else goes off or comes
      -- back with one, and staging records a choice and writes nothing. Required, since a page
      -- whose whole reason is these has nothing honest left to show without them.
      pluginCatalog = { source = "root", policy = "required",
        breaks = "the Olm Plugins page has nothing to list, since which plugins exist and what "
          .. "each needs is known only to the root that read the manifests" },
      pluginCascade = { source = "root", policy = "required",
        breaks = "the Olm Plugins page cannot say what else goes off with a plugin before it is "
          .. "switched off, or what comes back with it" },
      stagePluginSwitch = { source = "root", policy = "required",
        breaks = "choosing a plugin stages nothing, since the staged set lives in the root and "
          .. "has no other way in from this plugin" },
      -- Saves the staged set and schedules the one reload, with the place this page describes
      -- reopened after it. Optional, since the root also applies when the stage goes away.
      applyPluginSwitches = { source = "root", policy = "optional",
        breaks = "the page cannot offer Apply now, so staged choices apply only when the stage "
          .. "is dismissed and nothing reopens after the reload" },

      -- One line of routine feedback, which is how a refused switch says why, and the stage word
      -- the pane follows the highlight through. Both optional.
      notify = { source = "root", policy = "optional",
        breaks = "a plugin that cannot be switched gives no reason, the press simply does nothing" },
      stageSelectedItem = { source = "root", policy = "optional",
        breaks = "the pane cannot be repainted after a switch, so it keeps describing the state "
          .. "from before the press until the highlight moves" },

      stagePresent = { source = "root", policy = "optional",
        breaks = "the Olm Plugins launcher row opens nothing, since M.show has no other way to "
          .. "reach the shared stage" },
    },
  },

  -- Opened from the launcher only, so it proposes no key.
  defaults = {
    description = "Olm Plugins",
  },

  surface = {
    context = "olmplugins",
    primary = { action = "insertSelected", description = "Switch" },
    -- The pane describing the highlighted plugin.
    pane = true,
  },

  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
    intercept = { member = "intercept", call = "dot" },
    onHighlight = { member = "onHighlight", call = "dot" },
    onPositioned = { member = "onPositioned", call = "dot" },
    onClose = { member = "onClose", call = "dot" },
    paneWidth = { member = "paneWidth", call = "dot" },
  },

  registry = {
    row = { category = "Olm", icon = "plugins",
      detail = "switch plugins on or off",
      keywords = "extensions, enable, disable, modules" },
    open = { member = "show", call = "dot" },
  },
}
