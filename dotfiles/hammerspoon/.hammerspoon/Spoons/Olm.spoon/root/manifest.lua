-- The composition root's own needs, which belong to no plugin.
--
-- Every other manifest in this tree describes a plugin. This one describes the root that wires
-- them, which reaches for three tools of its own. A need with nothing but the root behind it is
-- otherwise the one category nothing declares and so nothing checks, which is the same reason
-- the setup scripts one layer up declare stow and duti rather than assuming them.
--
-- Pure data like every other manifest, so the collector that builds this module's upward facing
-- manifest reads it without loading the root. It declares needs.tools and nothing else. It is
-- not a plugin, it claims no surface and provides nothing, and the plugin scan never sees it
-- since that reads the plugins and host directories alone. The root loads this itself and adds
-- what it declares to the set it hands the dependency door, so the door answers for the root on
-- the same terms as for a plugin and the root reaches for that tool by no name.
return {
  needs = {
    tools = {
      { name = "scutil", kind = "system", locator = "/usr/sbin/scutil", policy = "optional",
        unit = "compose",
        reason = "reading this machine's own short name, the key every per host answer a " ..
                 "plugin asks the root for is stored under",
        origin = { macos = "ships with the system" } },
      -- Required, because the leader remap is nothing but a front end onto this one binary.
      -- Without it no catalog row can be applied, which is every leader key at once. It was
      -- declared by the keyremap plugin until phase two of the core split moved the remap into
      -- the root, which is why the unit is still called keyremap, so the consumer label in the
      -- manifest the layer above reads keeps meaning what it meant. The shipping with the
      -- system origin is an ORIGIN and not a reason to stay silent, declaring is what tells
      -- that layer the tool is needed at all.
      { name = "hidutil", kind = "system", locator = "/usr/bin/hidutil", policy = "required",
        unit = "keyremap",
        reason = "applying the one HID mapping every leader key depends on, and clearing it " ..
                 "again on quit",
        origin = { macos = "ships with the system" } },
      -- Optional, because only the url form of bringing an app forward runs it, an app toggle
      -- or a launcher app row whose target is a settings pane rather than an application.
      -- Declared here since phase three of the core split moved that behaviour out of the app
      -- toggler into lib/appfocus.lua, which the root configures with this door, so the unit
      -- is named for the lib that runs it.
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional",
        unit = "appfocus",
        reason = "opening a pane url for an app toggle or a launcher app row whose target is " ..
                 "a settings pane rather than an application",
        origin = { macos = "ships with the system" } },
    },
  },
}
