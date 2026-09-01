-- LinkRouter, what it declares about itself.
--
-- Hammerspoon already ships http, https and mailto in its own Info.plist, so it can hold the
-- system default handler for a scheme without any second bundle existing anywhere. That is the
-- whole reason this plugin is possible at all, and it is worth stating here because a reader
-- who assumes a browser must be a separate signed app will look for one and never find it.
--
-- No browser is declared as a dependency, and none ever should be. Destinations are discovered
-- from LaunchServices at read time rather than named anywhere, so a browser installed tomorrow
-- appears on its own and no list in this repository has to learn about it. This plugin needs
-- none of them, it routes to whatever the machine happens to have, and it says so on an empty
-- list rather than breaking. The one tool it does declare is the open binary, and only because
-- naming a profile inside a browser is beyond what the bundle level door can express.
return {
  -- The directory is linkrouter, one lowercase word, while the identity everywhere outside
  -- this folder, the registry, the launcher row, and surface.context below, is linkRouter.
  name = "linkRouter",

  needs = {
    tools = {
      -- Only the Chromium provider ever asks for this, and only to name a profile inside a
      -- browser, which hs.urlevent.openURLWithBundle has no way to express since it can name
      -- an application and nothing inside it. Optional, and its absence costs profile routing
      -- alone, every profile free destination still opening through Hammerspoon's own door.
      { name = "open", kind = "system", locator = "/usr/bin/open", policy = "optional",
        unit = "providers/chromium",
        reason = "opening a link in one named profile of a Chromium browser, which the bundle "
          .. "level door cannot address",
        origin = { macos = "ships with the system" } },
    },
    data = {
      -- The door a clicked link comes through. Required rather than optional, which is the
      -- opposite of what every other launcher only tool declares, and the difference is real.
      -- Elsewhere a missing stage word costs one inert key press and the person presses it
      -- again. Here it would cost every link on the machine, silently, because this plugin
      -- claims the system default handler and a claim that cannot show a chooser is a link
      -- that goes nowhere at all. Refusing to wire is the honest failure, since the handler is
      -- only ever claimed from inside a wired plugin.
      stagePresent = { source = "root", policy = "required",
        breaks = "a clicked link opens nothing anywhere on this machine, since the router has "
          .. "no other way to reach the shared stage and the system handler has already been "
          .. "claimed by the time a link arrives" },

      -- The field carries the link being routed, which is the one piece of context the rows
      -- themselves deliberately do not repeat. Optional, and its absence costs wording rather
      -- than function, the list still routing correctly while saying less about what it is
      -- routing.
      stageSetPlaceholder = { source = "root", policy = "optional",
        breaks = "the field keeps the configuration page's own wording while a link is waiting, "
          .. "so the list no longer names the link it is about to open" },

      -- Copying a link is finished the moment it is copied, so the window goes rather than
      -- sitting there having already done its job. Optional, degrading to a list left open
      -- after a successful copy.
      stageHide = { source = "root", policy = "optional",
        breaks = "the list stays open after Copy link has already put the link on the clipboard" },

      -- The configuration page's own toggles rebuild the list they stand on. Optional, and
      -- without it a toggled row writes correctly but its own marker stays stale until the
      -- page is reopened.
      redrawPresented = { source = "root", policy = "optional",
        breaks = "a destination toggled or reordered on the configuration page keeps its old "
          .. "marker and its old place until the page is closed and opened again" },

      -- The two ordering keys act on whatever the highlight is on, which only the live widget
      -- can honestly answer. Optional, and without it both keys are inert rather than acting
      -- on some remembered row that may not be the one a person is looking at.
      -- The rules page is a child pushed from the configuration page, and a child can only ever
      -- push, so its own Back row needs this to leave.
      stagePop = { source = "root", policy = "optional",
        breaks = "the rules page's own Back row stands on the level it meant to leave rather "
          .. "than returning to the configuration page" },
    },
  },

  -- No provides. There is no useful typed scope here, since the router is never reached by
  -- typing, it is reached by clicking a link in another application entirely.

  -- Opened from the launcher only, and deliberately so. The router itself must never need a
  -- key, because the thing that opens it is a link click somewhere else, and the configuration
  -- page is rare enough that a key of its own would be a key spent on almost nothing.
  defaults = {
    description = "Link routing",
    launcherRow = true,
    glyph = "🔗",
    aliases = { "link", "links", "browser" },
  },

  surface = {
    context = "linkRouter",
    primary = { action = "insertSelected", description = "Choose" },

    -- No extra bindings at all, deliberately. Everything this plugin can do is an ordinary row
    -- you choose, so the only keys live here are the shared navigation ones every list has.
    -- Showing a destination and placing it in the order are one act, choosing it, which is what
    -- removed the ordering keys, and a private window is its own selectable destination rather
    -- than a modifier, which is what removed that key too.
  },

  -- The presentation contract, docs/PLUGIN-CONTRACT.md. One registered presentation serves two
  -- entry points, a link waiting to be routed and the configuration page, and rows below reads
  -- which of the two is live off state this module already holds. That is not a shortcut, it
  -- is forced. The root publishes stagePresent(name) and nothing that hands the stage an
  -- arbitrary page, so an identity gets exactly one top level presentation and a plugin with
  -- two genuine ways in has to answer both from that one. onPresent is what keeps the two
  -- honest, resetting the field wording every time this level becomes current, and onClose is
  -- what stops a link outliving the window it was offered in.
  --
  -- No matcher declared, so the shared fuzzy strategy filters. That is wanted here rather than
  -- merely tolerated, since typing two letters of a browser name and pressing Return is the
  -- fastest this interaction can be, and neither list carries a Back row that filtering could
  -- hide.
  presentation = {
    rows = { member = "rows", call = "dot" },
    select = { member = "select", call = "dot" },
    placeholder = { member = "placeholder", call = "dot" },
    intercept = { member = "intercept", call = "dot" },
    onPresent = { member = "onPresent", call = "dot" },
    onClose = { member = "onClose", call = "dot" },
  },

  -- Configure alone leaves this plugin deaf. Start is what installs the urlevent callback and
  -- reads the stored preference, and without it the plugin registers a launcher row and hears
  -- nothing. Start deliberately never claims the system handler. A claim is a LaunchServices
  -- change that outlives a reload on its own, so there is nothing to reclaim, and every claim
  -- costs a confirmation panel macOS puts up itself.
  wiring = {
    { method = "configure" },
    { method = "start" },
  },

  registry = {
    row = { category = "System", detail = "choose where links open", glyph = "🔗" },
    open = "show",
    -- No surface member. With no extra bindings to route, host/stage's own surfaceFor answers
    -- the generic navigation verbs from the presentation alone, the same way DisplayProfiles
    -- stopped declaring one.
  },
}
