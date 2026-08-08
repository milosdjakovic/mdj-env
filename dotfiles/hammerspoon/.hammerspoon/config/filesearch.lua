-- File search policy.
-- Pure data, no logic. The spoon's own root reads this and hands each piece to
-- whichever part needs it, so nothing below knows a source or a chooser exists.
--
-- Five things live here and they answer five different questions. `types` decides
-- what a dot attached token in a query means. `roots` decides what a bare directory
-- name resolves to. `searchAlso` decides where a search with no folder named starts
-- from, beyond home. `prune` decides what the hidden index refuses to walk. `preview`
-- decides how much of a file the pane beside the list reads before drawing it.

return {
  -- Type tokens. A query token written with a leading dot is a type filter when its
  -- remainder appears here, so `.js hello` means JavaScript files matching hello.
  -- Each entry maps the token to the extensions it covers, which is what lets one
  -- token stand for a family.
  --
  -- This does NOT have to be exhaustive, and that is the point of the design. A dot
  -- token that is absent from this table falls through to being a plain text search
  -- with hidden files included, and since an extension is part of a filename that
  -- still finds the files. So `.zst` finds every zst archive as text even with no
  -- entry here, it simply does not filter strictly. Add an entry when you want the
  -- strict filter or when one token should cover several extensions.
  types = {
    -- Families, the entries that genuinely earn a token
    img  = { "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg", "ico" },
    vid  = { "mp4", "mov", "mkv", "avi", "webm", "m4v" },
    aud  = { "mp3", "wav", "flac", "aac", "m4a", "ogg" },
    doc  = { "pdf", "doc", "docx", "pages", "rtf", "odt", "epub" },
    -- Sheets and slides kept apart from doc, since narrowing to one of them is the
    -- reason you would type a token at all
    xls  = { "xls", "xlsx", "numbers", "csv", "tsv" },
    ppt  = { "ppt", "pptx", "key" },
    arch = { "zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "dmg" },
    -- Source families, where one token standing for several extensions is the win
    js   = { "js", "mjs", "cjs", "jsx" },
    ts   = { "ts", "tsx", "mts", "cts" },
    web  = { "html", "htm", "css", "scss", "sass", "less" },
    cfg  = { "json", "yaml", "yml", "toml", "ini", "conf", "plist", "env" },
    -- Single extension entries, listed so the strict filter is available on the ones
    -- reached most often here. Anything missing still works as text, see above.
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

  -- Directory aliases. A query token ending in a slash is resolved against these
  -- first, so `dl/` and `downloads/` both reach the same place, then against a
  -- literal path, then against the frecency tool if one is available.
  --
  -- Paths are relative to the home directory, so nothing here names an absolute
  -- location and the same table works on any machine. A leading slash makes one
  -- absolute when that is genuinely meant.
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
    dev       = "Development",
    personal  = "Development/personal",
    config    = ".config",
    hs        = ".hammerspoon",
    -- Outside home, which is what the absolute form is for. Typing `/` on its own already
    -- browses the volume root with no alias at all, so `root` is only a shorter way to say it.
    apps      = "/Applications",
    root      = "/",
  },

  -- Extra starting points for a search with NO folder named, added to the ones derived from
  -- home. A search that names a folder is unaffected, since that one is answered by walking the
  -- tree you named.
  --
  -- The derived half is the top level of home minus the pruned names, and it is derived rather
  -- than written out because Spotlight cannot be told to leave a subtree out. Naming the siblings
  -- of ~/Library is the only way to exclude it, and that list has to keep up as folders come and
  -- go. So this one adds to it rather than replacing it.
  --
  -- An entry may be absolute, relative to home, or written with a tilde, and one that is not a
  -- directory on this machine is skipped, so the same list works everywhere.
  --
  -- Applications are the case this exists for. They live outside home, so they were unfindable,
  -- which also made the `app` type token above useless. Keep the list short for RELEVANCE and
  -- not for speed, because breadth here is close to free. Measured over three terms, the derived
  -- list, the whole of home and the whole volume all answered in the same 120 to 175 millisecond
  -- band once the index was warm, and reading a page of two hundred rows cost 3.5ms whether the
  -- result held 3,781 rows or 52,246. Adding "/" would therefore cost no time at all and would
  -- still be a bad trade, since every query would then compete with the system.
  searchAlso = { "/Applications", "/System/Applications" },

  -- What the hidden index refuses to walk. Spotlight indexes no path containing a
  -- dot segment, not the dot entry itself and not anything beneath it, so the hidden
  -- source walks that blind spot itself and keeps the result. This list is what keeps
  -- that walk from being pointless, since the bulk of a home directory's dot paths
  -- are package caches nobody searches for.
  --
  -- Measured on one machine, the walk with this list applied covers about 245
  -- thousand paths in a second, and without the cache like entries it is several
  -- times that with nothing gained. Editing this list is how you decide what unscoped
  -- hidden search can reach, so it is the one knob worth revisiting if something you
  -- expected to find is missing.
  prune = {
    "Library", "Backups", ".git", ".cache", ".Trash",
    ".npm", ".pnpm-store", ".yarn", ".bun", ".cargo", ".rustup", ".nvm", ".gem",
    ".venv", "venv", "__pycache__", ".gradle", ".m2", ".cocoapods",
    "node_modules", ".next", ".turbo", "target", ".terraform",
    -- The macOS custom folder icon, a file rather than a directory, and the trailing
    -- carriage return is part of its real name. Every other artifact of its kind is dot
    -- prefixed and therefore already out of an ordinary search, which is exactly why this
    -- one is the only one that ever showed up in a list. The filter matches a terminal
    -- path segment as well as an inner one, so naming a file here works, and the doc above
    -- already frames an entry as a name nobody searches for in either position.
    "Icon\r",
  },

  -- The pane beside the list, which describes the highlighted row. Every number here
  -- bounds work that happens once per highlighted row rather than once per row on
  -- screen, which is why reading a file at all is affordable here and is not in a list.
  preview = {
    -- How wide the pane is. The chooser itself is 480, so this is deliberately narrower,
    -- since the list is what you are steering and the pane is what you glance at. The
    -- Chooser atom caps a companion at 480 regardless.
    width = 420,

    -- How much of a file is read to show its head. Two hundred lines of source is around
    -- eight kilobytes, so this is generous enough that the cut is never what you are
    -- looking at, and small enough that the read stays imperceptible on a local disk.
    readCap = 64 * 1024,

    -- How many lines of that are kept. The pane scrolls, so this is how far it can be
    -- scrolled rather than how much is visible, and past a few hundred lines you want
    -- the file open in an editor rather than in a pane.
    headLines = 400,

    -- How far past that a file is shown whole anyway. A hard edge would trade the last few
    -- lines of a file that only just exceeds the budget for a notice about those same lines,
    -- which is a worse thing to be given. So a file of four hundred and fifteen lines is
    -- complete and silent, and only past four hundred and twenty is it trimmed and reported.
    headSlack = 20,

    -- How many entries of a folder are listed, newest first. The count over the heading
    -- is the real total, so a bigger folder still reports its size honestly.
    folderEntries = 100,

    -- The larger edge of a rendered picture, in pixels. Above the pane's own width so it
    -- stays sharp on a retina display, which draws it at twice the point size.
    imageEdge = 600,

    -- Past this, an image is not decoded in process. A decode happens on the main thread
    -- and Hammerspoon owns every leader key in this config, so a stall here is a stalled
    -- keyboard, and a photo library holds files well over this.
    --
    -- It routes rather than refuses. A file over it goes to Quick Look, which is another
    -- process and does not care how big the file is, so this is not a maximum size the pane
    -- can show. There is no such maximum.
    nativeMaxBytes = 20 * 1024 * 1024,

    -- Where rendered pictures are kept between opens, so a pdf costs a Quick Look render
    -- once rather than on every open. Outside the git tracked config, beside the other
    -- caches, and written with a tilde since nothing here names an absolute location.
    cacheDir = "~/.cache/hammerspoon/filesearch-previews",

    -- How many renders are kept before the oldest are dropped. Each is a small PNG, so
    -- this is about not growing without bound over months rather than about space.
    cacheFiles = 400,
  },

  -- Cloud mirrors and media libraries, pruned from the hidden walk for the same
  -- reason but kept separate because these are names on one machine rather than
  -- general package noise. Add whatever your home holds that is enormous and not
  -- worth indexing.
  pruneLocal = {
    "Google Drive", "DaVinci Resolve Media", "Sync",
  },

  -- Limits and timings. Every one of these was chosen against a measurement, so the
  -- comment says what the measurement was rather than asserting a number is right.
  limits = {
    -- How long after the last keystroke a search is dispatched. Below this a fast
    -- typist never pays for an intermediate query, above it the pause starts to read
    -- as lag.
    debounceMs = 70,

    -- Rows handed to the chooser. The row build is cheap, two hundred rows of icon
    -- lookups measured 6.6ms cold and 0.2ms through the shared cache, so this is
    -- about how much list is useful rather than about frame time.
    displayCap = 200,

    -- Rows kept in memory behind the displayed ones. Narrowing filters this retained
    -- set locally instead of dispatching again, and it is only valid while the set was
    -- not truncated, so retaining well above the display cap is what makes one round
    -- trip per search rather than one per keystroke the common case.
    retainCap = 2000,

    -- Shortest unscoped query that is dispatched at all. A one or two character
    -- search over a whole home matches so much that it is neither useful nor fast, so
    -- the recent list stays up instead. A scope lifts this, since the candidate set is
    -- already small.
    minChars = 3,

    -- How long a source may take before it is abandoned. Spotlight queries measured
    -- 109 to 155ms, a scoped walk 13ms on a small tree and 353ms on one holding 196
    -- thousand entries, so this is several times the worst observed case.
    timeoutSeconds = 5,

    -- How stale the hidden index may be before a rebuild is started in the background.
    -- Dotfile trees barely move, and the stale answer stays on screen while the fresh
    -- one is built, so this trades nothing for a walk that costs about a second.
    hiddenMaxAgeSeconds = 300,

    -- How many recent files fill the list before anything is typed, and how far back
    -- they may reach. This is the state the picker opens in, so it is answering what
    -- you touched lately rather than listing a directory.
    --
    -- The window used to be three days, on a measurement of 3,136 files in 207ms that was
    -- taken BEFORE the search scopes were narrowed to exclude ~/Library. Almost all of
    -- those were logs and caches, so once the noise was gone the same three days matched
    -- only 22 real files and the list was nearly empty. Seven days matches about 38
    -- thousand and gathers in under a tenth of a second, because only a page is ever read
    -- out of the result set and the gather itself is cheap. So this is no longer the
    -- setting that can make opening the picker slow, and it should be wide enough to be
    -- useful rather than as narrow as possible.
    --
    -- The count of files in a window is lumpy rather than smooth, since one checkout or
    -- install writes tens of thousands at once. On this machine six days matched 494 and
    -- seven matched 38,172. Nothing here depends on which side of such a step the window
    -- lands, which is the point of not tuning to it.
    recentCount = 40,
    recentDays = 7,

    -- How many of the files you actually use are floated to the top of that opening list,
    -- ahead of the ones ordered by date.
    --
    -- This is bounded rather than generous on purpose. Modification date answers what
    -- changed and your own history answers what you reach for, and both belong in that
    -- list, because right after a download or a build is exactly when this picker gets
    -- opened and a file that did not exist a minute ago has no history at all. Let the
    -- history fill the page and the view becomes the same handful of files forever, which
    -- is the opposite of what landing on it is for. So a few rows, then the dates.
    recentFloat = 8,

    -- How much your history is worth when you HAVE typed something.
    --
    -- Deliberately smaller than the gaps in the search ranking, which awards 1000 for the
    -- typed text appearing whole in a filename and 500 for every word appearing in it. So
    -- this reorders files that matched the query equally well and can never lift one that
    -- matched it worse. When there is a query the query is the strong signal, and only in
    -- the opening list, where there is no query, does history choose the rows outright.
    frecencyWeight = 300,

    -- How long a use takes to count half as much. Two weeks means the project you are on
    -- this month outranks the one you finished last month without ever forgetting it,
    -- and it is the only number that changes the character of the ranking.
    frecencyHalfLifeDays = 14,

    -- How many paths to remember before the weakest are dropped. The store is one small
    -- number per path, so this is about keeping the list meaningful rather than about
    -- space, and a few hundred is far more than the set of files anyone actually returns to.
    frecencyMaxEntries = 500,
  },
}
