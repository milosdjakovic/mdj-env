# Presentation contract, second revision, 2026-08-27

Two extensions forced by the trickle migrations, filesearch, processes, and clipboard
all resist the version one contract on grounds the builder correctly refused to paper
over. Decisions by the orchestrator, to be built with the three migrations and
reviewed as one.

## The gap

One, the matcher. The stage's single instance inherits the root's fuzzy default at
construction for the life of the config, while all three plugins declare their own
matching policy, filesearch and clipboard disabling atom matching outright because
their engines rank structured queries themselves, processes preferring word matching
over fuzzy for digit and path heavy haystacks. The native provider reads its matcher
live on every build, only construction captures it, so a live write works exactly the
way paneWidth already does.

Two, deferred entry. Processes' own documented rule is that its picker never appears
before its async scan lands, and present calls onPresent then show synchronously, so
nothing a presentation starts can delay the first appearance. VPN and menu search
tolerate the show then correct shape, processes' author explicitly rejected it, and
the wiring layer does not get to overrule a plugin's own design record.

## Decisions

1. The presentation gains matcher, optional, false meaning the supplier owns
   filtering, or a string naming a strategy in Chooser.matchers. The stage writes the
   resolved value onto the live instance before every show and swap, restoring the
   root default when the field is absent, the same live mutation discipline
   companionWidth already follows, commented as such. The registrar validates the
   string against the names the Chooser atom exports, refusing loudly on an unknown
   one.

2. The presentation gains enter, optional, a member called instead of an immediate
   push when the tool is chosen from a row or a hotkey. It receives one function,
   proceed, which shows this presentation when called, so a tool that must gather
   before appearing scans first and proceeds after, while a tool without enter keeps
   today's immediate behavior. The stage stays ignorant of why a tool defers. The
   launcher remains up and responsive until proceed runs, so choosing processes feels
   like the list swapping once the scan lands rather than a window blinking empty.
   proceed called twice is a no op the second time, proceed called after the stage
   moved on, the person escaped or opened something else meanwhile, is dropped by
   the same staleness discipline the redraw word already follows, and enter must
   arrange its own timeout the way the VPN and menu search walks already do so an
   answer that never comes cannot strand a person on a launcher row that silently
   does nothing.

3. Both fields join PLUGIN-CONTRACT.md's presentation section with the call kind rule
   applying to enter, and BRIEF-STAGE.md's field list, in the same commit that builds
   them.

## Scope

The contract extension plus the three migrations, filesearch, then processes, then
clipboard, per the standing trickle instructions, one commit for the extension and
one per migration. One adversarial review over the four commits, one gate.
