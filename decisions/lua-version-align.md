# Lua version alignment

Status. Every offline gate of the hammerspoon module runs the Lua that Hammerspoon embeds, resolved through mise from a version the module's own runtime-probe reads out of the installed app, and the reconciler reports a catalog row that does not match. Built 2026-10-28, not yet installed on this machine.

## Now

Hammerspoon compiles its own Lua into the app, 5.4.7 at the time of writing, and the version is a fact about the installed build. The module ships `runtime-probe` at its package root, which finds the application by the bundle id its own declaration carries and prints `lua 5.4` from the banner inside LuaSkin. Every offline gate in the Olm spoon's test directory sources `embedded-lua.sh`, which asks that probe, asks mise where that version of lua is installed, checks the interpreter's own `_VERSION` against the answer and sets `OLM_LUA`. No gate names a version or a bare `lua`. The interpreter is the `lua5.4` row of `dotfiles/mise/TOOLS`, which a machine takes through its tools row. `src/check-dependencies.sh` runs every module's `runtime-probe` and reports an error when the catalog has no row for the runtime and version a module embeds, and a warning when a probe cannot answer here. `dependencies-collect` stays on plain Homebrew lua, since it runs where mise may not and reading a manifest is the same on every Lua. `OLM_LUA_OVERRIDE` runs the gates on a named interpreter without the version check, only to prove a gate under another Lua on purpose.

## Rejected

Running the gates on whatever lua is on PATH, Homebrew's 5.5.1. Rejected 2026-10-28 11:34. That is what was done, and a change to `root/compose.lua` passed every offline gate and then failed to load live, because Lua 5.4 limits a function to 200 locals and 5.5 accepted it.

Adding `lua@5.4` to the Brewfile. Rejected 2026-10-28, proposed and corrected the same day. A language runtime lives in the mise catalog and never in Homebrew, which is rule 5 for machines and runtimes in AGENTS.md, and a Homebrew lua@5.4 would also be keg only and a second copy to keep in step.

Writing the version into each gate. Rejected 2026-10-28. Seven scripts and a nested call would each carry a number that has to move with the app, and the one that was missed would pass on the wrong Lua again. The version is read from the app once and the gates name nothing.

## Log

2026-10-28 11:34, estimated from the failed live load. A change to `root/compose.lua` passed drygate, the goldens and the plain Lua tests on Lua 5.5.1, then failed to load in Hammerspoon with too many local variables, limit 200, in `obj.run`. The embedded Lua was 5.4.7, read from the string `$LuaVersion: Lua 5.4.7` inside LuaSkin in the app bundle. Commit 2ff3e7e6 moved the wiring off the 200 locals. The record of the failed load is in olm-swift-chooser.md.

2026-10-28 12:30. Built the alignment. `runtime-probe` and `embedded-lua.sh` are new, the `lua5.4` row is in the catalog and on this machine's tools row at the person's approval, the reconciler checks every probe by name, and the module declares mise, strings and osascript beside lua. Run with `OLM_LUA_OVERRIDE` on Homebrew's 5.5.1, drygate, the dry suite and the goldens all pass. Without the override they stop with the message naming the row and the step, since mise has not installed lua 5.4 here yet.

### 2026-10-28 12:55

Installed through the mise step on this machine, lua 5.4.9 from the `lua5.4` row, and every
offline gate of the hammerspoon module then ran on it with no override, the dry gate with its
rename proof, the goldens and the dry suite, all green, and the reconciler found the catalog row
agreeing with the Lua the installed Hammerspoon embeds. A side effect worth knowing, the mise step
puts the row in the machine's own mise config, so `lua` on PATH in a shell with mise active is
now 5.4.9 rather than Homebrew's 5.5.1, which the collector does not mind.
