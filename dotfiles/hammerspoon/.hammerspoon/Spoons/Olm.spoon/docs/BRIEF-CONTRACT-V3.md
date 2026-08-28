# Presentation contract, third revision, child presentations, 2026-08-28

Orchestrator decision from Milos's direction of 2026-08-28, a plugin with nested
lists should get drill in and back for free from the stage's existing stack rather
than hand wiring intercept and back per level. The stack already exists and already
does this for launcher to tool, this revision only opens it to the plugins.

## Decisions

1. A presentation's onSelect may return a presentation table. The stage pushes the
   returned table as a child, exactly as a launcher row pushes a tool, so choosing
   such a row swaps the list in place, backspace on an empty field pops back to the
   parent, and every morphing rule applies per level, a child may declare its own
   paneWidth, matcher, placeholder, rowCount, or none and inherit the defaults.
   Returning nil or nothing keeps today's meaning, the row completed and the stage
   hides. The mechanism rides the existing intercept chain inside the stage, the
   plugin writes no hook.

2. A child needs no name of its own, the stage derives context from the owning
   presentation so hints and navigation keep working, though a child MAY carry a
   name when its level genuinely wants different hint content.

3. intercept and back remain in the contract for the one case a child cannot
   express, a row that mutates the list it is on and stands, the clipboard's prune
   page being the canonical case. A plugin needing levels uses children, a plugin
   needing in place mutation uses intercept, and the contract documents when each
   is right.

4. The migrations of displayprofiles and browsertabs use children for their level
   stacks rather than intercept plumbing. Plugins already migrated onto intercept
   levels, tmuxsessions and clipboard's manage history if committed that way,
   convert in the close out sweep, not now, behavior first, ergonomics second.

5. PLUGIN-CONTRACT.md and BRIEF-STAGE.md document the returned child in the same
   commit that builds it.
