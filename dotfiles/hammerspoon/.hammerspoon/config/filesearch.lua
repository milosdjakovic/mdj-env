-- File search policy.
-- Pure data, no logic. The spoon's own root reads this and hands each piece to
-- whichever part needs it, so nothing below knows a source or a chooser exists.
--
-- Five things live here and they answer five different questions. `types` decides
-- what a dot attached token in a query means. `roots` decides what a bare directory
-- name resolves to. `searchAlso` decides where a search with no folder named starts
-- from, beyond home. `prune` decides what the file index never descends into. `preview`
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

  -- Extra starting points for the file index, crawled beside home and searched by every query
  -- with NO folder named. A search that names a folder is unaffected, since that one is answered
  -- by walking the tree you named.
  --
  -- An entry may be absolute, relative to home, or written with a tilde, and one that is not a
  -- directory on this machine is skipped, so the same list works everywhere.
  --
  -- Applications are the case this exists for. They live outside home, so without this they are
  -- unfindable, which also makes the `app` type token above useless. Each entry is crawled on
  -- every rebuild, so adding "/" would multiply the index and the rebuild time, and every query
  -- would then compete with the system.
  searchAlso = { "/Applications", "/System/Applications" },

  -- Folder names the file index never descends into, and a scoped walk skips too. The
  -- bulk of a home directory is package caches and build output nobody searches for by
  -- name, and leaving them out is what keeps the index small and its rows worth showing.
  --
  -- Measured on 2026-10-30, the crawl with this list applied covered 160 thousand
  -- entries in 1.2 seconds. Editing this list is how you decide what unscoped search can
  -- reach, so it is the one knob worth revisiting if something you expected to find is
  -- missing.
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
    -- keyboard. It is also memory, since an in process decode is the whole picture at full
    -- size, a phone photo near 48MB, held by Hammerspoon until the picker closes. Quick Look
    -- hands back a picture the size of the pane, near 1.4MB, so anything but a small image
    -- goes there, at the price of a moment on its first preview, cached after that.
    --
    -- It routes rather than refuses. A file over it goes to Quick Look, which is another
    -- process and does not care how big the file is, so this is not a maximum size the pane
    -- can show. There is no such maximum.
    nativeMaxBytes = 1024 * 1024,

    -- Where rendered pictures are kept between opens, so a pdf costs a Quick Look render
    -- once rather than on every open. Outside the git tracked config, beside the other
    -- caches, and written with a tilde since nothing here names an absolute location.
    cacheDir = "~/.olm/cache/filesearch/previews",

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

    -- Rows kept in memory and handed to the chooser, where the shared search ranks them and
    -- the presentation's rowLimit shows the best two hundred. Narrowing ranks this retained
    -- set again instead of dispatching, and it is only valid while the set was not
    -- truncated, so retaining well above what is shown is what makes one round trip per
    -- search rather than one per keystroke the common case. The display cap that sat here
    -- until phase three of the unified search cut before any ranking, so it left the engine
    -- for the presentation's rowLimit.
    retainCap = 2000,

    -- Shortest unscoped query that is dispatched at all. A one or two character
    -- search over a whole home matches so much that it is neither useful nor fast, so
    -- the recent list stays up instead. A scope lifts this, since the candidate set is
    -- already small.
    minChars = 3,

    -- How long a source may take before it is abandoned. An index search measured about
    -- 10ms, a scoped walk 13ms on a small tree and 353ms on one holding 196 thousand
    -- entries, so this is several times the worst observed case.
    timeoutSeconds = 5,

    -- How stale the file index may be before an open rebuilds it in the background. The
    -- stale answer stays on screen while the fresh one is built, and a rebuild measured
    -- about a second, so this bounds how far behind a just saved file can be.
    indexMaxAgeSeconds = 300,

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
