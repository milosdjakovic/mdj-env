-- Stage, what it declares about itself.
--
-- A host, and the one place in this configuration that ever calls Chooser.new. Every list
-- tool used to build its own instance and its own window. This host owns the single live
-- instance every presentation shows into, built once at configure and never rebuilt, per the
-- stage design brief's own first decision.
--
-- It declares no surface of its own. What it shows on screen is always a presentation someone
-- else handed it, never a list this host built itself, so there is no context here for the
-- nav registry to bind and no chord of its own to propose. The navigation adapter it does
-- expose, stage.surface, is reached through whichever plugin's own manifest already names a
-- surface, the launcher's today, unchanged. Declaring a surface here would make this host a
-- thirteenth navigable context with nothing of its own to navigate, which is the opposite of
-- what it is for.
--
-- Because it opens no context, it earns none of the ambient grant a surfaced plugin gets for
-- free, the chooser factory, the theme, and a placeholder. Every one of those is asked for
-- directly instead, the same values the ambient grant would have handed over, so the request
-- says what it needs rather than pretending to be a kind of plugin it is not.
return {
  needs = {
    data = {
      -- The chooser facade, lib/chooser, the one door this host reaches to build its instance.
      -- Root sourced because it is the shared atom the composition root already builds and
      -- configures once, before any manifest is even read.
      chooser = { source = "root", policy = "optional",
        breaks = "the stage has nothing to build its one instance with, so no presentation, the launcher included, has anywhere to show" },
      -- The shared theme, the same palette every surfaced plugin already receives ambiently.
      theme = { source = "root", policy = "optional",
        breaks = "the one instance falls back to the atom's own minimal dark palette instead of the configured theme" },
      -- What the field reads for the instant between construction and the first present, since
      -- a presentation's own placeholder is not applied until that presentation is current.
      -- Cosmetic only, nothing is ever typed before a presentation exists to read it.
      placeholder = { source = "root", policy = "optional",
        breaks = "the field carries the atom's own bare default until the first presentation sets its own" },
      -- The docked shortcut panel triple. Fixed for the life of this one instance rather than
      -- carried on a presentation, per the stage design brief's own decision that panel
      -- callbacks are atom level policy alongside screen, matcher, and theme, not something a
      -- presentation may override. Phase two hands this the launcher's own panel, the only one
      -- that exists yet, and later phases are what teach the panel to follow whichever
      -- presentation is current.
      onPositioned = { source = "root", policy = "optional",
        breaks = "the docked shortcut panel never arms, so no hint bar ever appears beneath whatever the stage is showing" },
      onActivity = { source = "root", policy = "optional",
        breaks = "the docked shortcut panel's idle countdown never resets on a keypress, so it can reveal itself mid type" },
      onClose = { source = "root", policy = "optional",
        breaks = "the docked shortcut panel is never told to hide, so it can survive past the list it was pinned under" },
    },
  },

  -- No defaults. This host opens no list of its own, has no key, and proposes nothing a
  -- person could override.
  defaults = {},
}
