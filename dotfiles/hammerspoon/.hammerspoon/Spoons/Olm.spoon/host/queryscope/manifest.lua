-- QueryScope, what it declares about itself.
--
-- A host rather than a plugin, and the distinction is the whole reason this file looks
-- different from a plugin's. A plugin knows only itself. A host knows that a SET of plugins
-- exists and composes across it, while never learning which ones are in it.
--
-- That is what `needs.set` is for. It is a question about the set rather than a name, so the
-- answer is computed from what the plugins themselves declared.
return {
  needs = {
    -- Every plugin that can be reached by typing its alias. The pair is the requirement and
    -- both halves matter. `rows` alone is a computed source that claims nothing, which is a
    -- different job, so asking for both is what separates a scopable tool from a calculator.
    -- Whichever plugin still lacks a `provides` for this pair earns it there, never a
    -- hardcoded name here, that is the whole point of asking the set a question instead of
    -- naming a roster.
    set = {
      scopes = { provides = { "rows", "select" } },
    },

    -- The shared filter strategy every surfaced plugin inherits ambiently the moment it
    -- declares a surface. This host declares none, a query source is not a Hyper context, so
    -- it earns nothing that way and has to ask for the value directly.
    --
    -- This used to be needs.lib.matcher naming a module called match. That named the wrong
    -- grain, this plugin wants one function, not the whole strategies table, and it named the
    -- wrong mechanism besides. A lib need only proves a module exists, it is never actually
    -- injected into configure, the ambient grant that does the injecting is keyed off
    -- declaring a surface, which this host cannot do. So the real request is Olm's own
    -- obligation to hand over whichever strategy it made the shared default, which is exactly
    -- what needs.data with source root already means.
    --
    -- What this still cannot say is that the answer must be THE SAME strategy every surfaced
    -- plugin gets, rather than some other function that happens to match today. Naming it here
    -- as a fixed member, match.fuzzy for instance, would freeze today's default and go stale
    -- the moment the root's own shared choice changes, which is worse than the gap it would
    -- paper over.
    data = {
      matcher = { source = "root", policy = "optional",
        breaks = "a scope shaped like a list stops ranking its rows against what was typed, since the plain substring or dynamic program that would otherwise score them is never handed in" },
    },
  },

  -- The grammar itself, one word then a separator, is this host's own and not configurable,
  -- so there is nothing to propose. It has no key, no chooser, and no launcher row, because
  -- it is reached only by typing inside a list that is already open.
  defaults = {},
}
