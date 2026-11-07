# Bridge

The Lua side of Olm.app, the native app `docs/PLAN-STANDALONE.md` moves Olm into. Today it does one
thing, step 1.2. Where this machine's `olmapp` piece is on and the app is built, file search's open
key opens the app's file search through `olm://filesearch` rather than the Lua one.

It shows nothing and binds nothing itself. The root asks it which tools the app serves, after the
keymap is built, and hands each such tool's open key its function. The keymap is unchanged, so the
key, its cheat sheet row and its launcher row stay where they are, and the Lua file search is still
reached from the launcher. Switching the piece off gives the key back on the next load.
