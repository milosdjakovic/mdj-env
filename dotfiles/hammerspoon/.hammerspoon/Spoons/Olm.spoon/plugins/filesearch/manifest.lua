-- FileSearch, what it declares about itself.
--
-- Five tools across four files, a walker that finds what Spotlight cannot see, a
-- ranker over that walk, a Quick Look renderer for the side pane, and a compiler for
-- the native Quick Look panel that leads it. fd is declared twice, once beside the
-- unscoped hidden search and once beside the scoped walk, since each file names it
-- for its own reason and neither should have to learn the other exists.
return {
  -- The directory is filesearch, one word, while the identity everywhere outside
  -- this folder, config/keys.lua, the registry, the launcher row, is fileSearch.
  name = "fileSearch",

  needs = {
    tools = {
      { name = "qlmanage", kind = "system", locator = "/usr/bin/qlmanage", policy = "optional", unit = "thumbs",
        reason = "drawing a preview of a pdf, a video, or anything else only Quick Look can render",
        origin = { macos = "ships with the system" } },
      -- swiftc is absent on a fresh install until the command line tools go on, unlike
      -- qlmanage above, which is why this one line names an install step rather than
      -- claiming the compiler already ships with the system.
      { name = "swiftc", kind = "system", locator = "/usr/bin/swiftc", policy = "optional", unit = "quicklook",
        reason = "compiling the helper that opens the native Quick Look panel",
        origin = { ["xcode-clt"] = "xcode-select --install" } },
      { name = "fd", kind = "path", policy = "optional", unit = "hidden",
        reason = "building the index of paths Spotlight cannot see",
        origin = { brew = "fd" } },
      { name = "fzf", kind = "path", policy = "optional", unit = "hidden",
        reason = "ranking that index, the one thing a substring tool cannot do over 42 thousand matches",
        origin = { brew = "fzf" } },
      { name = "fd", kind = "path", policy = "optional", unit = "walk",
        reason = "walking a named directory, which is faster than the index once a scope is given and is the only way to see dotfiles",
        origin = { brew = "fd" } },
    },

    data = {
      -- Everything in config/filesearch.lua, the type token registry, the directory aliases,
      -- the prune list, the read caps and the cache location. Genuinely the person's own, since
      -- which folders matter and which noise to skip is a fact about their machine rather than
      -- anything shippable, and this plugin deliberately ships none of it.
      --
      -- Optional, and the sentence below is why. Every consumer of the policy already treats an
      -- absent slice as nothing configured, so the tool still opens, still searches, and still
      -- ranks. It simply does it over the whole disk with no vocabulary.
      --
      -- One slice of it IS shippable, and saying otherwise above was wrong. Which folders
      -- matter is personal, and so is a name that only appears on one machine, but a list of
      -- package and build caches nobody ever searches for is the same on every Mac. node_modules
      -- is node_modules everywhere. So that slice ships, and the rest still waits for a person.
      --
      -- Laid under anything supplied rather than over it, so a person handing over their own
      -- policy keeps every key they wrote, and one handing over a policy with no prune list of
      -- their own still gets this. A person who wants a different list writes one and it replaces
      -- this outright, because a list is a complete statement, which is lib/defaults.lua's rule
      -- rather than a new one invented here.
      --
      -- Icon\r is a file rather than a directory and the trailing carriage return is part of its
      -- real name, which is why it is the only artifact of its kind that ever reached a list,
      -- every other one being dot prefixed and already out of an ordinary search.
      policy = { source = "user", policy = "optional",
                 default = {
                   -- Extension families. Universal by nature, png is png on every machine, and a
                   -- token absent here still works as a plain text search, so this list decides
                   -- where the STRICT filter is available rather than what can be found at all.
                   types = {
                     img  = { "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg", "ico" },
                     vid  = { "mp4", "mov", "mkv", "avi", "webm", "m4v" },
                     aud  = { "mp3", "wav", "flac", "aac", "m4a", "ogg" },
                     doc  = { "pdf", "doc", "docx", "pages", "rtf", "odt", "epub" },
                     xls  = { "xls", "xlsx", "numbers", "csv", "tsv" },
                     ppt  = { "ppt", "pptx", "key" },
                     arch = { "zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "dmg" },
                     js   = { "js", "mjs", "cjs", "jsx" },
                     ts   = { "ts", "tsx", "mts", "cts" },
                     web  = { "html", "htm", "css", "scss", "sass", "less" },
                     cfg  = { "json", "yaml", "yml", "toml", "ini", "conf", "plist", "env" },
                     lua  = { "lua" },
                     py   = { "py", "pyi" },
                     go   = { "go" },
                     rs   = { "rs" },
                     sh   = { "sh", "bash", "zsh", "fish" },
                     md   = { "md", "markdown", "mdx" },
                     txt  = { "txt", "text", "log" },
                     swift = { "swift" },
                     java = { "java", "kt" },
                     c    = { "c", "h" },
                     cpp  = { "cpp", "cc", "hpp", "cxx" },
                     rb   = { "rb" },
                     php  = { "php" },
                     sql  = { "sql" },
                     app  = { "app" },
                   },
                   -- The standard macOS folders, every one relative to home so the same table
                   -- works anywhere, plus the two absolute ones. A person's OWN project folders
                   -- are the part that cannot ship, since nobody else knows what they are called,
                   -- and this is a map so adding one keeps every alias below.
                   roots = {
                     downloads = "Downloads",
                     dl        = "Downloads",
                     documents = "Documents",
                     docs      = "Documents",
                     desktop   = "Desktop",
                     pictures  = "Pictures",
                     pics      = "Pictures",
                     movies    = "Movies",
                     music     = "Music",
                     home      = "",
                     config    = ".config",
                     hs        = ".hammerspoon",
                     apps      = "/Applications",
                     root      = "/",
                   },
                   -- Applications live outside home, so without this the app type token above
                   -- finds nothing at all. Both paths exist on every Mac, and an entry that is
                   -- not a directory here is skipped, so the list travels.
                   searchAlso = { "/Applications", "/System/Applications" },
                   prune = {
                     "Library", "Backups", ".git", ".cache", ".Trash",
                     ".npm", ".pnpm-store", ".yarn", ".bun", ".cargo", ".rustup", ".nvm", ".gem",
                     ".venv", "venv", "__pycache__", ".gradle", ".m2", ".cocoapods",
                     "node_modules", ".next", ".turbo", "target", ".terraform",
                     "Icon\r",
                   },
                   -- The pane beside the list. Shipped because nothing else answers for it, no
                   -- consumer carries a fallback for any of these, so an absent table left the
                   -- pane with no read cap and nowhere to keep a render. Numbers rather than
                   -- taste, each one bounding work that happens once per highlighted row.
                   preview = {
                     readCap = 64 * 1024,
                     headLines = 400,
                     headSlack = 20,
                     folderEntries = 100,
                     imageEdge = 600,
                     nativeMaxBytes = 20 * 1024 * 1024,
                     cacheDir = "~/.cache/hammerspoon/filesearch-previews",
                     cacheFiles = 400,
                   },
                   -- limits is deliberately NOT here. engine.lua already merges it against its
                   -- own DEFAULTS table, so shipping it again would put one fact in two files and
                   -- let them drift, which is the whole failure this repository keeps removing.
                   -- pruneLocal is not here either, for the opposite reason, it is names on one
                   -- machine by its own definition.
                 },
                 breaks = "this person's own project folder aliases and the enormous "
                   .. "directories only their machine holds are absent, so those names resolve to "
                   .. "nothing and the hidden walk descends into whatever they keep that is not "
                   .. "general package noise" },
      -- Repaint a surface other than this plugin's own picker, for the case where the file list
      -- is being shown inside the launcher. Composed with the picker's own redraw rather than
      -- replacing it, so both are told and each ignores it when it is not on screen.
      redraw = { source = "root", policy = "optional",
                 breaks = "a file list hosted inside another surface stops updating as answers "
                   .. "land, so it shows whatever had arrived by the time the last keystroke was "
                   .. "painted and nothing after it" },
    },
  },

  -- Scoped by the launcher, the alias is the slash itself, matching the tool's own
  -- key, so typing it lists the same rows the picker does and choosing one does the
  -- same thing.
  provides = {
    rows = "rows",
    select = "select",
  },

  -- Slash reads as search, the way it does in vim and in every browser find.
  --
  -- The two viewer seats are named here, BY NAME, and that is what lets this tool preview
  -- anything on a machine with nothing configured. They used to be chosen outside, by reference
  -- to one of this plugin's own internal modules, which only a root allowed to name a concretion
  -- inside a plugin could do. Once no such root existed both seats sat empty. The docked one
  -- silently fell back to the side panel, so it looked fine, and the peek seat did not, so Quick
  -- Look was gone along with the key that asks for it and the row that advertises it.
  --
  -- They are two seats rather than one because they answer different callers. sidepanel follows
  -- the highlight and reserves room beside the list, quicklook opens over the picker only when a
  -- key asks and reserves nothing. Swapping them yields a tool with no preview at all, since a
  -- viewer that does not follow the highlight cannot fill the docked seat. Either may be set to
  -- false to decline that seat outright, which is different from leaving it unset.
  --
  -- The names are previewWith and peekWith rather than the previewProvider and peekProvider this
  -- plugin's own configure used to read, and the difference is load bearing rather than taste. A
  -- default declared here reaches the opts table of EVERY wiring step, the chooser submodule's own
  -- configure included, so a default sharing a name with one of that submodule's options
  -- overwrites whatever the plugin root had already resolved for it. That is not theoretical. As
  -- peekProvider it reached the chooser as the bare word quicklook, landed on the field that
  -- expects a viewer, and the picker then raised on start every single time it opened.
  defaults = {
    leader = "app",
    key = "/",
    description = "File search",
    glyph = "🗂️",
    aliases = { "/" },
    previewWith = "sidepanel",
    peekWith = "quicklook",
  },

  -- Five actions beyond the shared navigation, walking into and out of a folder,
  -- revealing a row, opening its enclosing folder, and copying its path. The two
  -- scroll bindings and the peek binding each carry a needs gate, since which of
  -- them means anything depends on which preview provider the root chose, the side
  -- pane or the native Quick Look panel.
  surface = {
    context = "fileSearch",
    primary = { action = "insertSelected", description = "Open" },
    extra = {
      { key = "j", mods = { "cmd" }, action = "scrollPreviewDown", needs = "scrollablePreview",
        description = "Scroll preview down" },
      { key = "k", mods = { "cmd" }, action = "scrollPreviewUp", needs = "scrollablePreview",
        description = "Scroll preview up" },
      { key = "q", action = "peekPreview", needs = "askedPreview", description = "Quick Look", glyph = "👁️" },
      { key = "l", action = "browseInto", description = "Into folder", glyph = "📂" },
      { key = "h", action = "browseUp",   description = "Up a level", glyph = "⬆️" },
      { key = "o", action = "revealInFinder", description = "Reveal in Finder", glyph = "🔍" },
      { key = "y", action = "copyPath",   description = "Copy path", glyph = "📋" },
    },
    -- A path is long text searched from the inside with a real remembered fragment,
    -- a project name or a folder, rather than an abbreviation of a short label, so
    -- this plugin wants the words matcher over fuzzy. It still opts its own Chooser
    -- instance out of the atom's own ranking, since the query is structured rather
    -- than a plain filter, so the words value reaches the engine instead, narrowing
    -- a held result set between round trips one layer down from everywhere else.
    matcher = "words",
    -- The pane beside the list is the one place a highlighted file's name, size,
    -- dates and a rendered preview live, so it earns the reserved room.
    pane = true,
  },

  -- This plugin's own configure already wires the api wave onto the chooser
  -- submodule, rowsFor, onUse, usedAt, the preview policy and the viewer chain, so
  -- calling configure(opts) on the plugin root is not the whole story but needs no
  -- extra step here. What configure alone never reaches is the view wave, the
  -- factory, the theme, the row icon memo, the copy seam and the panel triple, all
  -- of which land on the chooser submodule as a second call, plus the submodule's
  -- own start before a picker exists to show at all.
  wiring = {
    { target = "chooser", method = "configure" },
    { target = "chooser", method = "start" },
  },

  -- Every one of these lives on the chooser submodule as a plain dot called function,
  -- function M.show(), never a colon method, so open and every scope action below say dot
  -- rather than taking the default. scopeRows is the one member the chooser did not use to
  -- expose. It joins M.ensureSession and M.rowsForQuery exactly the way M.show already asks
  -- for a session, so a scope entered on an empty query gets one going the same way opening
  -- the real picker does. matcher is false for the same reason the surface block above
  -- states one nowhere, the query is structured and the engine ranks its own held results.
  -- verbs mirrors the three real actions beyond choosing and previewing a row, each carrying
  -- closes exactly as the retired root's own registration stated it, since whether running a
  -- verb should close the list it ran against is this plugin's own fact about that verb.
  registry = {
    row = { category = "Tools", keywords = "find files folders spotlight locate" },
    open = { member = "chooser.show", call = "dot" },
    surface = "chooser",
    hosted = true,
    shortcut = "leader",
    scope = {
      matcher = false,
      rows = { member = "chooser.scopeRows", call = "dot" },
      run = { member = "chooser.choose", call = "dot" },
      peek = { member = "chooser.peekRow", call = "dot" },
      verbs = {
        revealInFinder = { member = "chooser.revealRow", call = "dot", closes = true },
        copyPath = { member = "chooser.copyPathRow", call = "dot", closes = true },
        peekPreview = { member = "chooser.peekRow", call = "dot", closes = false },
      },
    },
  },
}
