-- DisplayMemory, what it declares about itself.
--
-- The reusable Observer mechanism only, watching one app's windows and persisting the
-- display each lands on. Everything the composition root hands it, the bundle id to watch,
-- the settings key, and the scope naming the current location, is plain data or a closure
-- the root owns rather than a capability from a sibling plugin or from Olm's lib. It has no
-- chooser, no key, and no alias, its whole surface is the rememberedScreen answer another
-- mechanism reads directly, so this plugin is infrastructure with no user surface of its
-- own.
--
-- Two of the three configure fields earn a line below. settingsKey is left out on purpose,
-- since configure already falls back to a working default, "displayMemory", so nothing
-- breaks by omitting it, the same reasoning that keeps WindowMemory's tolerance and
-- settleDelay undeclared.
return {
  needs = {
    data = {
      -- The app to watch, resolved by the composition root from the person's own preferred
      -- terminal app and their own apps registry. Nothing here could stand in for either
      -- choice, so a missing bundle id is not a value this plugin could ever default to.
      bundleID = { source = "user", policy = "required",
                   breaks = "start becomes a silent no op, nothing is ever watched and rememberedScreen answers nil forever" },
      -- The closure naming the current location, displayFingerprint in the composition
      -- root, built from the attached displays. Root computed rather than the person's own
      -- knowledge, and the same closure WindowMemory and DisplayProfiles must also receive,
      -- though nothing here can assert that the three share the identical function.
      scope = { source = "root", policy = "optional",
                breaks = "every location shares one remembered display slot instead of each one keeping its own, so undocking can silently hand back a display that belongs to a different desk" },
    },
  },
}
