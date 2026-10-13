# Phase four, the provider is chosen at the root

Read docs/PLAN-CANVAS-CHOOSER.md first, decisions one and the checklist, and
docs/CONTRACT-PICKER.md. Work only in the worktree this file is in.

## What to build

One setting picks which picker provider every Chooser.new builds, native or canvas. Native
stays the default, so a machine that says nothing behaves exactly as today.

## The shape

The facade, lib/chooser/init.lua, exposes its providers as a table the same way it already
exposes `obj.matchers`, so `obj.providers = { native = ..., canvas = ... }`. Chooser.configure
takes `opts.provider`, a provider module, and new() builds through it, still validating every
instance against contract.lua before decorate runs. When nothing is configured, new() falls
back to native, the same fallback rule DEFAULT_SCREEN and DEFAULT_MATCHER already follow.

The composition root, root/compose.lua, picks the module from policy the same way it already
picks the matcher, `chooserAtom.providers[policy.chooserProvider]`, beside the existing
matcher line in the chooserAtom.configure call. Olm's own shipped policy default at the top
of compose.lua names native. An unknown name logs one warning naming the bad value and falls
back to native rather than failing the load.

The user config passes it through. config/settings.lua gains a `chooserProviders` constant
table beside `overlayModes`, exported the same way, and a `chooser = { provider =
chooserProviders.native }` block with a short comment saying what canvas changes and that
native is the default. init.lua passes `chooserProvider = settings.chooser.provider` in the
policy table. The constant values are the provider names the facade's table uses.

## Before you write the wiring

Check that the canvas provider accepts every config field the two live construction sites
pass, host/stage/init.lua and host/actionpanel/init.lua through decorate, and that it reads
`config.theme` the way compose.lua supplies it. Report any field the canvas provider ignores
that native honours. Do not fix provider behaviour in this phase, list it.

## Acceptance

- `./test/units.sh` from dotfiles/hammerspoon/.hammerspoon still shows 561 assertions with
  only the known actionpanel substring failure, plus any new cases you add for the facade
  choosing a provider and falling back on an unknown one.
- `luac -p` clean on every file touched.
- `src/check-dependencies.sh` from the repo root of the worktree reports nothing new.
- Do not reload Hammerspoon, do not take the devlock, do not drive the screen, do not commit.

## Writing style, a hard requirement

Comments in plain sentences with only periods and commas. No dashes of any kind, no colons
or semicolons in prose. Match the comment density of the surrounding code.
