-- The composition root's own needs, which belong to no plugin.
--
-- Every other manifest in this tree describes a plugin. This one describes the root that wires
-- them, which reaches for two tools of its own. A need with nothing but the root behind it is
-- otherwise the one category nothing declares and so nothing checks, which is the same reason
-- the setup scripts one layer up declare stow and duti rather than assuming them.
--
-- Pure data like every other manifest, so the collector that builds this module's upward facing
-- manifest reads it without loading the root. It declares needs.tools and nothing else. It is
-- not a plugin, it claims no surface and provides nothing, and the plugin scan never sees it
-- since that reads the plugins and host directories alone. The root loads this itself and adds
-- what it declares to the set it hands the dependency door, so the door answers for the root on
-- the same terms as for a plugin and the root reaches for neither tool by name.
return {
  needs = {
    tools = {
      { name = "scutil", kind = "system", locator = "/usr/sbin/scutil", policy = "optional",
        unit = "compose",
        reason = "reading this machine's own short name, the key every per host answer a " ..
                 "plugin asks the root for is stored under",
        origin = { macos = "ships with the system" } },
      { name = "displayplacer", kind = "path", policy = "optional",
        unit = "overlaydisplay",
        reason = "turning a display serial id into a live screen, so an overlay can be " ..
                 "pinned to one physical display",
        origin = { brew = "displayplacer" } },
    },
  },
}
