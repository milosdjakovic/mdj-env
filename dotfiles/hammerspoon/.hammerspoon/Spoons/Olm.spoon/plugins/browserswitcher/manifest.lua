-- Browser Switcher, what it declares about itself.
--
-- Olm.app is the default browser and hands every link it receives to this plugin through
-- provides.links, docs/DESIGN-BROWSER-SWITCHER.md, and the list asks which browser, profile or
-- Copy Link. Native Lua over hs.urlevent and
-- hs.application, and the browsers are whatever this Mac has registered for https, so it names no
-- tool. One behaviour, so the whole plugin is init.lua.
return {
  apiVersion = 1,

  about = {
    title = "Browser Switcher",
    description = "Ask which browser or profile opens each link you click.",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },

  -- The directory is browserswitcher, one word, the identity everywhere else browserSwitcher.
  name = "browserSwitcher",

  icons = {
    browser = { emoji = "🌐", sf = "globe" },
    copy = { emoji = "📋", sf = "doc.on.doc" },
    open = { emoji = "↗️", sf = "arrow.up.right.square" },
    all = { emoji = "📃", sf = "list.bullet" },
    favourites = { emoji = "⭐", sf = "star" },
    warn = { emoji = "⚠️", sf = "exclamationmark.triangle" },
  },

  needs = {
    data = {
      favourites = { source = "user", policy = "optional",
        breaks = "the list shows every browser and profile, then Copy Link" },
      stagePresent = { source = "root", policy = "optional",
        breaks = "a link cannot ask, so Olm.app opens it in Safari" },
      stageSetPlaceholder = { source = "root", policy = "optional",
        breaks = "the list's field does not name the link it is asking about" },
      redrawPresented = { source = "root", policy = "optional",
        breaks = "Show All and Show Favourites change nothing until the list opens again" },
      stageHide = { source = "root", policy = "optional",
        breaks = "Copy Link from the actions pane leaves the list open" },
      notify = { source = "root", policy = "optional",
        breaks = "a copied link, a new default browser or a rule naming nothing installed says nothing" },
    },
  },

  -- Olm.app's links come here, found by this capability and never by name.
  provides = {
    -- A dot function, M.link(params), so the call is stated, since the default is a method call and
    -- handed every link to the module table in the place of params.
    links = { member = "link", call = "dot" },
  },

  defaults = {
    description = "Browser Switcher",
    icon = "browser",
  },

  -- Return opens the link in the highlighted browser, Command and Return copies it. Show All and
  -- Show Favourites swap the list between the favourites and every browser this Mac has.
  surface = {
    context = "browserSwitcher",
    primary = { action = "insertSelected", description = "Open", icon = "open" },
    secondary = { action = "copyLink", description = "Copy Link", icon = "copy" },
    extra = {
      { action = "showAll", description = "Show All", icon = "all", applies = "isFavourites" },
      { action = "showFavourites", description = "Show Favourites", icon = "favourites", applies = "isAll" },
    },
  },

  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
  },

  -- Drawn on this plugin's own page in Olm Settings, the favourites laid over before configure.
  settings = {
    -- Read and changed by Olm.app, since which app opens a link is the Mac's, never stored here.
    { key = "defaultBrowser", kind = "handler", scheme = "https", title = "Default Browser",
      detail = "Choose Olm so the links you click come here. macOS asks before it changes.",
      keywords = { "default browser", "http", "url handler" } },
    { key = "favourites", at = { "favourites" }, title = "Favourites", kind = "picks", source = "browsers",
      fixed = { "Copy Link" }, shipped = {},
      detail = "What the list shows when a link asks. With none checked it shows every browser and profile, then Copy Link. Show All in the actions pane lists the rest.",
      keywords = { "browser", "profile", "picker" } },
  },

  registry = {
    row = { detail = "open the last link elsewhere", icon = "browser",
      keywords = "default browser, url, link, profile, chrome, safari, firefox" },
    open = { member = "show", call = "dot" },
    surface = "verbs",
  },
}
