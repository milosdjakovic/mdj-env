-- KeyRemap, what it declares about itself.
--
-- The HID level applier only, turning a name based catalog into one hidutil mapping and
-- clearing it on quit. It decides which key is active nowhere, the composition root passes
-- the catalog and the active names into apply rather than into configure, and both are
-- plain data, so there is nothing here from a sibling plugin or from Olm's lib. hidutil
-- ships with macOS, so there is no tool to declare either. It has no chooser, no key of its
-- own, and no alias, every key it touches belongs to whichever domain referenced it, so
-- this plugin is infrastructure with no user surface of its own.
--
-- Its whole lifecycle is one call, apply(catalog, activeNames), and that call is not
-- configure(opts), so the call itself belongs here rather than in an empty return. Both
-- values it needs are shippable, not personal, so they are defaults rather than a needs.data
-- entry with policy required. Caps Lock to F18, Right Option to F16, and Right Command to
-- F17 are the exact three rows the owner already wants HYPER, META, and SUPER to be, and
-- they work on any keyboard, so a fresh install ships them rather than asking the person for
-- something Olm already knows.
--
-- Which of the three are ACTIVE is deliberately not shipped here, and that is the one
-- interesting decision in this file. A catalog key is active only by being REFERENCED, so
-- the set follows from which leader each domain claims, app toggles naming one and window
-- management naming another. Writing the answer down as a static list here would look
-- harmless and would quietly cost the property that makes the catalog worth having, that
-- moving all of window management to another physical key is ONE edit. With a list here it
-- becomes two, the domain's choice and this copy of the consequence, and the day someone
-- changes one and not the other a leader is either remapped for nothing or referenced and
-- never remapped. So the root computes it from what the domains reference and hands it in.
--
-- It is required rather than optional because an empty active set remaps nothing, which
-- takes down every leader at once. Sourcing it from the root rather than the user is what
-- keeps that from blocking a fresh install, since the root always discharges it.
return {
  needs = {
    data = {
      activeNames = { source = "root", policy = "required",
        breaks = "no catalog row is active, so hidutil remaps nothing and every leader key, "
          .. "the app toggles and the window leader alike, stays its own native key" },
    },
  },

  defaults = {
    catalog = {
      HYPER = { source = "capsLock",     fkey = "f18" },
      META  = { source = "rightOption",  fkey = "f16" },
      SUPER = { source = "rightCommand", fkey = "f17" },
    },
  },

  -- apply's own shape, apply(catalog, activeNames), is not configure(opts), so it is named
  -- here as a wiring step rather than assumed. The catalog is this plugin's own shipped
  -- default and reads from self. The active set is the root's answer about the whole plugin
  -- set and reads from root, which is the split the two namespaces exist for.
  wiring = {
    { method = "apply", args = { "self.catalog", "root.activeNames" } },
  },
}
