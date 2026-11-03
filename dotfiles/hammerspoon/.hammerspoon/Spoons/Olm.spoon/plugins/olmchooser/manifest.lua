-- Olm Chooser, what it declares about itself.
--
-- A friendly front end onto which chooser draws every list. It owns no data of its own, it only
-- reads and writes the choice through the root words below, and it never learns the names of the
-- choosers, only the titles each one declares for itself.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Olm Chooser",
    description = "Choose which chooser draws every list, the glass or the canvas.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The rows say chosen and wear Olm's own radio pair, so these are only the plugin's own icon
  -- and its Choose verb's.
  icons = {
    chooser = { emoji = "🗂️", sf = "rectangle.stack" },
    choose = { emoji = "✅", sf = "checkmark.circle" },
  },

  needs = {
    data = {
      -- The reader answers the title of the chooser that serves, the lister the titles of every
      -- chooser a person can pick, and the writer takes a title, persists it and schedules one
      -- reload, since which chooser draws is decided once per load. All three are required, since
      -- a list that cannot name the live chooser, list the choices or change one has nothing
      -- honest left to show.
      chooserName = { source = "root", policy = "required",
        breaks = "the Olm Chooser list cannot mark the chooser in use, since which provider "
          .. "serves has no other door out" },
      chooserNames = { source = "root", policy = "required",
        breaks = "the Olm Chooser list shows no choosers, since the providers are known only to "
          .. "the chooser facade the root built" },
      setChooser = { source = "root", policy = "required",
        breaks = "choosing a chooser changes nothing, since persisting it and reloading has no "
          .. "other way in from this plugin" },
      stagePresent = { source = "root", policy = "optional",
        breaks = "the Olm Chooser launcher row opens nothing, since M.show has no other way to "
          .. "reach the shared stage" },
    },
  },

  -- Opened from the launcher only, so it proposes no key.
  defaults = {
    description = "Olm Chooser",
  },

  surface = {
    context = "olmchooser",
    primary = { action = "insertSelected", description = "Choose", icon = "choose" },
  },

  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    intercept = { member = "intercept", call = "dot" },
  },

  registry = {
    row = { settings = true, icon = "chooser",
      detail = "how every list is drawn",
      keywords = "glass, canvas, native, provider, picker, look" },
    open = { member = "show", call = "dot" },
  },
}
