--- Processes row icons and framework naming.
---
--- Two jobs that look separate and are not. Deciding what a row IS and deciding what
--- to draw for it are the same lookup, because the thing that makes a row recognisable
--- is the framework rather than the interpreter underneath it. Two rows both reading
--- "node" tell you nothing, while one reading Next and one reading Vite tell you which
--- window to go close. So the classification happens once and hands back both a word
--- and a picture.
---
--- This is display policy and it lives here rather than in a source on purpose. A
--- source reports what the kernel says, which is that the process is node, and that
--- stays true and stays searchable. Only the surface decides to call it Next. Pushing
--- the guess down into discovery would mean a source inventing a fact it cannot see,
--- and the merge in the engine reasons about ports and pids, never about labels.
---
--- WHY NERD FONT GLYPHS RATHER THAN IMAGE FILES. An icon here is a codepoint plus a
--- colour, which is one table row, so a new technology costs a line rather than an
--- asset. The font is already a dependency of this repo, font-meslo-lg-nerd-font sits
--- in the Brewfile because the terminal, the prompt and the editor all need it, so
--- nothing new is installed and no binary is committed. Vector glyphs also stay sharp
--- at any size and take their colour from us, which matters because most brand hexes
--- are tuned for white documentation pages and go muddy on a dark row. The tints below
--- are deliberately lifted off the official values where that happened.
---
--- ONLY MARK GLYPHS, NEVER WORDMARKS. Several of the devicon codepoints are whole
--- words drawn into one character cell, nginx and django and the php text logo among
--- them. At the 21 point size a row draws they are illegible smears. Every glyph here
--- was rendered and looked at before it was added, and a technology whose only glyph is
--- a wordmark gets its runtime icon instead, which is honest rather than decorative.
---
--- A rule may name a label and no icon, and that is the normal case rather than a gap
--- to fill later. Astro and Gunicorn and Sidekiq have no glyph in the font, so they
--- correct the word and leave the picture alone, and the row still gains most of the
--- value. Inventing an approximate icon for them would be worse than the runtime one.

local M = {}

--------------------------------------------------------------------------------
-- The font
--------------------------------------------------------------------------------

-- Resolved once at load, not per row. A missing font renders every glyph as a hollow
-- box, which reads as a broken picker rather than a missing dependency, so the whole
-- set falls back to emoji instead. That is the degradation path for a machine this
-- repo has not set up, and it is why the emoji table below still exists.
local PREFERRED = {
  "MesloLGS-NF-Regular", "MesloLGSNF-Regular",
  "MesloLGLNF-Regular", "MesloLGMNF-Regular",
}

local function resolveFont()
  local installed = {}
  local ok, names = pcall(hs.styledtext.fontNames)
  if not ok or not names then return nil end
  for _, n in ipairs(names) do installed[n] = true end
  for _, want in ipairs(PREFERRED) do
    if installed[want] then return want end
  end
  -- Any Nerd Font will do, since the codepoints are the same across the whole family
  -- of patched fonts. Sorted so the choice does not wander between launches.
  local candidates = {}
  for _, n in ipairs(names) do
    if n:match("NerdFont.*Regular$") or n:match("NF%-Regular$") or n:match("NF$") then
      candidates[#candidates + 1] = n
    end
  end
  table.sort(candidates)
  return candidates[1]
end

local FONT = resolveFont()

--------------------------------------------------------------------------------
-- The glyphs
--------------------------------------------------------------------------------

-- glyph, tint, and an optional font override. A nil font means the Nerd Font, and
-- "system" means draw it in the normal UI font, which is how a plain Unicode shape
-- gets in. Next has no glyph in any Nerd Font block but its actual mark is a filled
-- triangle, so the ordinary character is not a substitute, it is the right symbol.
local NERD = {
  -- Runtimes.
  node       = { "\u{e718}", "#6CC24A" },
  -- Neither Bun nor Deno has a mark in the font, and both are JavaScript runtimes, so
  -- they share the language badge rather than borrowing Node's hexagon, which would
  -- say something untrue about what is running.
  bun        = { "\u{e781}", "#F2E4C8" },
  deno       = { "\u{e781}", "#A6C8FF" },
  python     = { "\u{e606}", "#4B8BBE" },
  ruby       = { "\u{e739}", "#E04A42" },
  php        = { "\u{e608}", "#8B92D4" },
  java       = { "\u{e738}", "#F89820" },
  go         = { "\u{e626}", "#00ADD8" },
  rust       = { "\u{e7a8}", "#E5A176" },
  perl       = { "\u{e67e}", "#B39DDB" },
  dotnet     = { "\u{f013}", "#B98EE0" },

  -- Containers.
  docker     = { "\u{e650}", "#2496ED" },
  compose    = { "\u{e64f}", "#2496ED" },

  -- Servers and stores, where the technology is the whole identity.
  web        = { "\u{f0ac}", "#22B455" },
  database   = { "\u{e64d}", "#7FB3D5" },

  -- Frameworks.
  next       = { "\u{25b2}", "#EDEDED", "system" },
  nuxt       = { "\u{e643}", "#00DC82" },
  vite       = { "\u{f0e7}", "#FFC848" },
  react      = { "\u{e625}", "#61DAFB" },
  vue        = { "\u{e6a0}", "#42B883" },
  angular    = { "\u{e753}", "#DD1B16" },
  svelte     = { "\u{e697}", "#FF3E00" },
  webpack    = { "\u{e7b2}", "#8DD6F9" },
  typescript = { "\u{e628}", "#3178C6" },
  rails      = { "\u{e604}", "#E0402B" },
  django     = { "\u{e606}", "#44B78B" },
  laravel    = { "\u{e73f}", "#F05340" },

  -- Neither a runtime nor a framework, the two ends of the range.
  terminal   = { "\u{e795}", "#9AA0A6" },
  fallback   = { "\u{f013}", "#9AA0A6" },
}

-- Tints that fail on a light chooser, and only those. The native chooser follows the
-- system appearance, so half the time these are drawn on near white rather than on the
-- dark row every brand palette assumes. Most of the colours above survive the swap and
-- are deliberately absent here, since duplicating a working value into a second table
-- would mean two places to keep in step for no gain. What does not survive is anything
-- pale, Next being the clearest case, a near white triangle on a near white row is an
-- empty slot. Vercel draws that mark black on light backgrounds, so this table is
-- following each brand's own guidance rather than inventing a second palette.
local LIGHT = {
  next       = "#1A1A1A",
  bun        = "#8A7355",
  deno       = "#2B5EA8",
  vite       = "#C98A00",
  nuxt       = "#00A862",
  react      = "#0B96C2",
  webpack    = "#3D8FC7",
  node       = "#4E9635",
  database   = "#4A7FA5",
  php        = "#6B72B4",
  rust       = "#9C6644",
  java       = "#D97706",
}

-- The degradation path, used whole when no Nerd Font is installed. Deliberately not a
-- per key fallback, because a row of crisp glyphs with one stray emoji in it looks
-- worse than a consistent set of emoji.
local EMOJI = {
  node = "🟩", bun = "🥟", deno = "🦕",
  python = "🐍", ruby = "💎", php = "🐘", java = "☕", go = "🐹",
  rust = "🦀", perl = "🐫", dotnet = "🟪",
  docker = "🐳", compose = "🐳",
  web = "🌐", database = "🗄️",
  next = "▲", nuxt = "⛰️", vite = "⚡", react = "⚛️", vue = "🟩",
  angular = "🅰️", svelte = "🟧", webpack = "📦", typescript = "🔷",
  rails = "💎", django = "🐍", laravel = "🐘",
  terminal = "⌨️", fallback = "⚙️",
}

-- Runtime names the sources actually report, folded onto a glyph key. The left side is
-- whatever ps or lsof printed, so the versioned and aliased spellings all belong here.
local RUNTIME = {
  node = "node", nodejs = "node", ["node.js"] = "node",
  bun = "bun", deno = "deno",
  python = "python", python2 = "python", python3 = "python", pypy = "python",
  ruby = "ruby", irb = "ruby",
  php = "php", ["php-fpm"] = "php",
  java = "java", kotlin = "java", scala = "java",
  go = "go", golang = "go",
  rust = "rust", cargo = "rust",
  perl = "perl",
  dotnet = "dotnet",
  docker = "docker",
  nginx = "web", httpd = "web", apache2 = "web", caddy = "web", traefik = "web",
  postgres = "database", mysqld = "database", ["redis-server"] = "database",
  mongod = "database",
  bash = "terminal", zsh = "terminal", sh = "terminal", fish = "terminal",
}

--------------------------------------------------------------------------------
-- Framework detection
--------------------------------------------------------------------------------

-- An ordered chain, first match wins, and the order is the whole design. Every needle
-- is a plain substring rather than a pattern, so nothing here has to be escaped and a
-- stray dash or dot in a tool name cannot quietly become a wildcard.
--
-- The signals cost nothing, which is the reason this is worth doing at all. The full
-- argv and the working directory are already on the row from the scan, so classifying
-- is string work over data in hand, with no extra shellout, no file read, and no
-- second pass over the process table.
--
-- Needles are chosen to be things a tool prints about itself rather than things that
-- merely appear near it. Next and Puma rewrite their own process titles, so
-- "next-server" and "puma" are the tool announcing what it is. Where the only signal
-- is a path, the needle carries enough of the path to be unambiguous, which is why
-- Vite looks for "/vite" and not "vite", so a project directory named "invite" is not
-- suddenly a dev server.
--
-- An entry is { label, iconKey, needles }. A nil iconKey means the word is corrected
-- and the runtime's own icon is kept, which is the right answer whenever the font has
-- no mark for that framework.
local RULES = {
  -- Node, most specific first, since half of these run through the same wrapper and a
  -- loose rule higher up would swallow the ones below it.
  { "next",       "next",       { "next-server", "/next/dist/bin", "next dev", "next start" } },
  { "nuxt",       "nuxt",       { "nuxt dev", "/nuxt/bin", "nuxi" } },
  { "vite",       "vite",       { "/vite", "vite.config", "vite dev", "vite build" } },
  { "astro",      nil,          { "/astro/", "astro dev" } },
  { "remix",      nil,          { "remix-serve", "remix vite" } },
  { "gatsby",     nil,          { "gatsby develop", "/gatsby/" } },
  { "storybook",  nil,          { "storybook" } },
  { "nest",       nil,          { "@nestjs", "nest start" } },
  { "angular",    "angular",    { "@angular/cli", "ng serve" } },
  { "vue",        "vue",        { "vue-cli-service", "@vue/cli" } },
  { "svelte",     "svelte",     { "svelte-kit", "sveltekit", "/svelte" } },
  { "react",      "react",      { "react-scripts" } },
  { "webpack",    "webpack",    { "webpack" } },
  { "ts-node",    "typescript", { "ts-node", "tsx watch" } },

  -- Ruby.
  { "rails",      "rails",      { "rails server", "bin/rails", "/rails" } },
  { "puma",       nil,          { "puma" } },
  { "sidekiq",    nil,          { "sidekiq" } },
  { "jekyll",     nil,          { "jekyll serve" } },

  -- Python.
  { "django",     "django",     { "manage.py runserver", "manage.py", "django" } },
  { "flask",      nil,          { "flask run" } },
  { "uvicorn",    nil,          { "uvicorn" } },
  { "gunicorn",   nil,          { "gunicorn" } },
  { "celery",     nil,          { "celery" } },

  -- PHP.
  { "laravel",    "laravel",    { "artisan serve", "artisan" } },
  { "symfony",    nil,          { "symfony serve", "bin/console" } },

  -- Everything else worth naming.
  { "hugo",       nil,          { "hugo server" } },
  { "spring",     nil,          { "spring-boot", "springboot" } },
  { "compose",    "compose",    { "docker-compose", "docker compose" } },
}

-- Everything the rules may look at, as one lowercased string. The full argv first
-- because that is where a tool names itself, then the working directory, which catches
-- a project laid out conventionally even when the invocation says nothing useful.
local function haystackFor(row)
  local parts = {}
  if row.commandFull and row.commandFull ~= "" then parts[#parts + 1] = row.commandFull end
  if row.command and row.command ~= "" then parts[#parts + 1] = row.command end
  if row.cwd and row.cwd ~= "" then parts[#parts + 1] = row.cwd end
  return table.concat(parts, " "):lower()
end

local function classify(row)
  local hay = haystackFor(row)
  if hay == "" then return nil, nil end
  for _, rule in ipairs(RULES) do
    for _, needle in ipairs(rule[3]) do
      -- Plain find, the fourth argument, so the needle is text and never a pattern.
      if hay:find(needle, 1, true) then return rule[1], rule[2] end
    end
  end
  return nil, nil
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- Cached because the supplier runs on every keystroke and building a canvas per row
-- per character would be absurd. Keyed on what was actually drawn rather than on the
-- glyph key, so two keys sharing a shape and differing only in tint, python and django
-- being exactly that, each keep their own picture.
local cache = {}

local function render(glyph, tint, font)
  local id = glyph .. "|" .. (tint or "") .. "|" .. (font or "")
  local hit = cache[id]
  if hit ~= nil then return hit or nil end
  local size = 28
  local cv = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  local el = {
    type = "text", text = glyph, textSize = 21, textAlignment = "center",
    frame = { x = 0, y = 0, w = size, h = size },
  }
  if font then el.textFont = font end
  if tint then el.textColor = { hex = tint, alpha = 1 } end
  cv[1] = el
  local img = cv:imageFromCanvas()
  cv:delete()
  cache[id] = img or false
  return img
end

-- Which way round the chooser is drawing. Read once and held, rather than per row per
-- keystroke, and refreshed when the picker opens, which is the only moment the answer
-- can have changed since anyone last looked. Nil means light, since interfaceStyle
-- reports only the dark case.
local isDark = nil
local function appearanceIsDark()
  if isDark == nil then
    local ok, style = pcall(hs.host.interfaceStyle)
    isDark = (ok and style == "Dark") or false
  end
  return isDark
end

-- One key in, one image out, whichever set is in play. The emoji path passes no font
-- and no tint, since a colour emoji ignores both. The cache key already carries the
-- resolved tint, so the two appearances keep separate pictures and switching back does
-- not redraw anything that was drawn before.
local function imageFor(key)
  key = key or "fallback"
  if not FONT then
    return render(EMOJI[key] or EMOJI.fallback, nil, nil)
  end
  local entry = NERD[key] or NERD.fallback
  local font = entry[3]
  if font == "system" then font = nil else font = FONT end
  local tint = entry[2]
  if not appearanceIsDark() then tint = LIGHT[key] or tint end
  return render(entry[1], tint, font)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

--- icons.emoji(str) -> hs.image
--- A literal character rendered the same way, for the fixed affordances that are not
--- technologies at all, the empty state and the two confirmation answers. They stay
--- emoji whatever the font situation is, because none of them is a brand.
function M.emoji(str)
  return render(str, nil, nil)
end

--- icons.badge(row) -> hs.image, label
--- The image for the row and the word to call it. The label is nil when nothing beat
--- the runtime, and the caller keeps whatever it already had.
---
--- A container is never run through the rules. Its command field holds an image name,
--- so a container built from nginx would classify as a web server and lose the whale,
--- and the whale is the one thing that says at a glance which rows are containers.
--- Compose is the exception, because that is still a container fact.
function M.badge(row)
  local runtime = (row.runtime or ""):lower()
  local runtimeKey = RUNTIME[runtime]

  if runtimeKey == "docker" then
    local hay = haystackFor(row)
    if hay:find("compose", 1, true) then return imageFor("compose"), nil end
    return imageFor("docker"), nil
  end

  local label, iconKey = classify(row)
  return imageFor(iconKey or runtimeKey), label
end

--- icons.refresh()
--- Forget the cached system appearance, so the next row picks its tint again. Called
--- when the picker opens, which is the one moment it is worth asking, and cheap because
--- the drawn images are cached on the tint rather than on the key.
function M.refresh()
  isDark = nil
end

--- icons.usingFont() -> string or nil
--- Which font the glyphs are coming from, or nil when the set degraded to emoji.
--- Diagnostic only, so a machine drawing the wrong thing can be asked why.
function M.usingFont()
  return FONT
end

return M
