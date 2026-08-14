-- WindowMemory, what it declares about itself.
--
-- The reusable mechanism only, DisplayMemory widened from one app to every window and from
-- a stored display to a stored frame. Everything the composition root hands it, the scope
-- naming the current location, the pixel tolerance, and the settle delay, is plain data,
-- none of it a capability from a sibling plugin or from Olm's lib. It has no chooser, no
-- key, and no alias, it watches and restores on its own once started, so this plugin is
-- infrastructure with no user surface of its own.
--
-- tolerance and settleDelay are left undeclared on purpose, since configure already falls
-- back to a working default for each, 5 pixels and 1.5 seconds, so omitting either changes
-- nothing observable. scope is the one field with no safe stand in.
return {
  needs = {
    data = {
      -- The closure naming the current location, displayFingerprint in the composition
      -- root, built from the attached displays. Root computed, and the same closure
      -- DisplayMemory and DisplayProfiles must also receive, though nothing in this
      -- manifest, or in any manifest, can assert that all three share the identical
      -- function rather than three separately built copies that happen to agree today.
      scope = { source = "root", policy = "optional",
                breaks = "every location shares one remembered layout instead of each keeping its own, so arriving at a different desk can silently restore the wrong location's frames" },
    },
  },
}
