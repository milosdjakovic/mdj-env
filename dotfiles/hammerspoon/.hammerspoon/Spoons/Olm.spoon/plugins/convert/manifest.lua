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

  -- The only thing this plugin proposes, and the first defaults block it has ever had. One
  -- short line for the launcher's empty field, saying that a quantity typed with a target
  -- after the word to answers here, which is otherwise discoverable only by a person who
  -- already knows it. It names the same operator the row builder accepts, so the hint and the
  -- grammar cannot drift, and it stays short enough for the field, which holds about twenty
  -- eight characters.
  --
  -- A distance to miles was the first wording here and it was wrong for a reason the field
  -- itself never shows. Customary length and speed both carry the tool's own mixed unit
  -- default, feet and inches rather than one decimal number, so that wording answered a sum
  -- and cost this plugin's own _run a second qalc process on the very first thing a curious
  -- person tried. A customary speed converted to a metric one resolves to one clean number
  -- on the first ask instead, the same shape init.lua's own isSingleValue already checks
  -- for, so the example a person sees costs exactly what the row it inspired will.
  --
  -- Nothing shows it when the calculator is absent, since a plugin left out for a missing
  -- required tool is left out of the launcher's source list too, and the hints are collected
  -- from that same list. So the field never advertises a conversion this machine cannot do.
  defaults = {
    example = "Try 10 mph to kph",
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
