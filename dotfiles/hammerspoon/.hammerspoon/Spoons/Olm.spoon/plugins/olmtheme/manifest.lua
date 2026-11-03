-- Olm Theme, what it declares about itself.
--
-- A friendly front end onto lib/ui/themes.lua. It owns no data of its own, it only reads and
-- writes the live theme through the root words below.
return {
  -- The contract this manifest was written against, see apiVersion in docs/PLUGIN-CONTRACT.md.
  apiVersion = 1,

  about = {
    title = "Olm Theme",
    description = "Pick the look of the chooser in use, a theme on the canvas or a highlight on the glass.",
    author = "Milos Djakovic",
    version = "0.3",
    license = "MIT",
  },

  -- The rows say chosen and wear Olm's own radio pair, so the only icon here is the plugin's own.
  icons = {
    theme = { emoji = "🎨", sf = "paintpalette" },
  },

  needs = {
    data = {
      -- The theme switcher's three words, published by the root over lib/ui/themes.lua. The
      -- reader answers the live theme's name, the lister the sorted names of every theme file
      -- found, and the writer takes a name, applies that theme at once and persists it. All
      -- three are required, since a list that cannot name the live theme, list the choices or
      -- change one has nothing honest left to show.
      themeName = { source = "root", policy = "required",
        breaks = "the Olm Theme list cannot mark the live theme, since the store of themes has "
          .. "no other door out" },
      themeNames = { source = "root", policy = "required",
        breaks = "the Olm Theme list shows no themes, since the files under config/themes are "
          .. "known only to the store the root built" },
      setTheme = { source = "root", policy = "required",
        breaks = "choosing a theme changes nothing, since applying and persisting a theme has "
          .. "no other way in from this plugin" },
      themeLabel = { source = "root", policy = "optional",
        breaks = "the Olm Theme list's field reads Theme rather than naming what the chooser in "
          .. "use offers, Canvas Theme or Glass Highlight" },
      stagePresent = { source = "root", policy = "optional",
        breaks = "the Olm Theme launcher row opens nothing, since M.show has no other way to "
          .. "reach the shared stage" },
    },
  },

  -- Opened from the launcher only, so it proposes no key.
  defaults = {
    description = "Olm Theme",
  },

  surface = {
    context = "olmtheme",
    primary = { action = "insertSelected", description = "Apply" },
  },

  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    intercept = { member = "intercept", call = "dot" },
  },

  registry = {
    row = { settings = true, icon = "theme",
      detail = "the look of the chooser in use",
      keywords = "colour, color, appearance, palette, dark, light, highlight, accent" },
    open = { member = "show", call = "dot" },
  },
}
