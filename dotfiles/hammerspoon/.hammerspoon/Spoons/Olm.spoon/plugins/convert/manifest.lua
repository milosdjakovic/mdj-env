-- Convert, what it declares about itself.
--
-- A front end onto one calculator tool with nothing to offer without it, so qalc is
-- required rather than optional, and a missing one leaves the root excluding this
-- plugin from the launcher's row sources entirely rather than wiring a dead one. It
-- has no defaults and no surface, unlike every other plugin in this set, because it
-- is not a key or a launcher row at all, it is a computed row source consulted on
-- every keystroke the same way Arithmetic is, and it has no entry anywhere in
-- config/keys.lua and no hyperContext of its own.
return {
  needs = {
    tools = {
      { name = "qalc", kind = "path", policy = "required",
        reason = "evaluating unit and currency conversions",
        origin = { brew = "libqalculate" } },
    },
    -- The resolved absolute path this tool arrives at is not named again here. It is
    -- already the whole point of the required line above, ambient through opts.deps, the
    -- same dependency door every declared tool goes through and the one thing declaring a
    -- tool at all earns.
    --
    -- This comment used to say the root handed this one plugin a bare opts.path instead,
    -- and that was simply not true. Nothing sent that field, so the plugin held no path
    -- and answered an empty list to every conversion typed at it, for as long as the
    -- manifest layer has existed. A comment describing a wiring nobody performs is worse
    -- than no comment at all, since it is the thing a reader checks the code against.
    data = {
      -- The answer to a conversion arrives after the row that asked for it was already
      -- built, since the calculator runs as a separate process. Without a way to say so,
      -- a landed answer only appears the next time the launcher rebuilds its rows on its
      -- own, typically the next keystroke, rather than the moment it is ready. Root
      -- computed, a closure the composition root builds over the launcher's own refresh.
      -- Optional, because the plugin's own comment says so plainly, omitting it leaves the
      -- answer to appear later rather than never.
      --
      -- Named redraw, which is the root's own one word for repainting whichever list is on
      -- screen, and shared with every other plugin that answers later than the keystroke did.
      -- It was onResult, a name only this plugin used, and a root value is delivered by field
      -- name, so a vocabulary of one word per plugin is a vocabulary nobody can pay.
      redraw = { source = "root", policy = "optional",
        breaks = "a landed conversion answer waits for the next keystroke to appear " ..
                 "instead of redrawing the row the moment it is ready" },
    },
  },

  -- The only thing this plugin proposes, and the first defaults block it has ever had. A
  -- list now rather than the one line this used to be, since one plugin covers several kinds
  -- of conversion and a single example could only ever teach one of them. Each line says
  -- that a quantity typed with a target after the word to answers here, which is otherwise
  -- discoverable only by a person who already knows it. Every line names the same operator
  -- the row builder accepts, so a hint and the grammar cannot drift, and each stays short
  -- enough for the field, which holds about twenty eight characters.
  --
  -- A distance to miles was the first wording here and it was wrong for a reason the field
  -- itself never shows. Customary length and speed both carry the tool's own mixed unit
  -- default, feet and inches rather than one decimal number, so that wording answered a sum
  -- and cost this plugin's own _run a second qalc process on the very first thing a curious
  -- person tried. Every line below was run against the real tool with this plugin's own
  -- flags before it shipped, and answers one clean value with no retry.
  --
  -- Temperature needed respelling to get there. 72 f to c and 72 F to degC both parse as
  -- farads and coulombs rather than degrees, since the tool's short unit names collide with
  -- electrical ones, and the fix is spelling both sides out, fahrenheit and celsius, which
  -- costs nothing this field cannot afford. Currency was checked carefully rather than
  -- assumed, since this plugin's own flags freeze the exchange rate file rather than fetch
  -- one, and qalc's own bundled rate snapshot answered offline with no network involved, so
  -- the hint is honest about what a fresh install can already do without a refresh.
  --
  -- Nothing shows any of it when the calculator is absent, since a plugin left out for a
  -- missing required tool is left out of the launcher's source list too, and the hints are
  -- collected from that same list. So the field never advertises a conversion this machine
  -- cannot do.
  defaults = {
    example = {
      "Try 100 eur to usd",
      "Try 72 fahrenheit to celsius",
      "Try 5 lb to kg",
      "Try 10 mph to kph",
    },
  },

  -- queryRows rather than rows, on purpose. rows is what a scopable tool claims, a
  -- browsable list an alias can enter, and this plugin has none of that, no key, no
  -- launcher row, no alias. What it claims instead is the typed query itself, the
  -- same way Arithmetic does, so a search naming rows would also match every
  -- scopable tool and lose the one distinction that matters here. Folding the two
  -- together would let a calculator swallow the launcher catalog.
  provides = {
    queryRows = "rows",
  },
}
