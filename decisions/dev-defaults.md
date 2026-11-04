# Default editor for development files, and what a script can and cannot do about it

Status. The editor is the machine's `editor` row in `machines/`, a bundle id or none. The setup
step only reads every handler against it and notes a difference. `src/set-dev-defaults.sh`
applies it when the person chooses to, since on macOS 27 each type that moves is a dialog the
person answers, and `--check` confirms without raising one.

## Now

Which editor a machine wants is its `editor` row in `machines/<name>/pieces`, holding the app's
bundle id, since a row value holds no space, or `none`, the default. `machine.sh capture`
proposes whatever opens `.md` now and asks, and `machine.sh set editor BUNDLE_ID` writes the
person's answer. `setup-dev-defaults.sh --list` names the candidates, the apps Launch Services
has registered as an Editor of more than half of a handful of development types. The role
query is deprecated since macOS 12 with no replacement that keeps the role, so when it answers
nothing the list falls back to every app that can open the types. It is read through
`osascript` and JavaScript for Automation, which needs no compiler.

The setup step never changes a handler. With a row of none it says one line. Otherwise it runs
`set-dev-defaults.sh --check`, which reads every handler with `duti -x`, finds the extensions
that resolve to an invented `dyn.` type by asking Launch Services through empty probe files,
and exits 3 on a difference. The step prints the count and leaves a closing note naming the
command that applies it.

Applying is `set-dev-defaults.sh`, with no argument for the row or with an app name or bundle
id. It asks `duti -s` for every extension, then reads the handler back, and the readback is the
report. An extension already on the editor is counted as already, one that moved as changed,
one whose binding fails on a `dyn.` type as untyped, since Launch Services will not bind a
handler to those, and one still on its old handler after the call as pending. On a run where
nothing changed and nothing is pending it prints one line.

Pending is the case that matters and it is not a failure. On macOS 27, changing the default
handler of a type raises a dialog, naming the application that has the type and the one
asking for it, and the person chooses. `duti -s` returns zero the moment it has asked, before
the dialog is answered, so a script cannot know the outcome and cannot influence it. A fresh
machine where Zed is not yet the default will therefore raise one dialog per typed extension,
up to forty of them, on the first run, and the step says so and points at `--check` to
confirm, since a second apply asks for every change again. That is macOS's design, the same guard that already kept `.html` out of the list
because it is one of the three records that define the default browser, now applied to every
type. The step exits zero on pending, since a fact about one machine's screen is a warning and
never an error, which is the line `check-dependencies.sh` draws for a permission grant.

`duti -x` answers from what Launch Services would open the file with, which is a wider question
than which handler is bound to the type, so it names Zed for `.rs` on a machine where the
binding cannot attach at all. That is why the untyped case is read off the binding's own error
first, and the readback is consulted only after.

## Rejected

- **Trusting duti's exit code, the report the script gave until 2026-09-17.** The code is zero
  whether the handler moved, was already there, or is waiting on a dialog nobody has answered.
  "Bound 33 extensions" was printed on every run of every machine, and on this one it had never
  once been the thing that bound them.
- **Printing the per extension listing on every run.** 2026-09-17. A hundred identical lines on
  a no-op run, half the log of `setup.sh`, in a run whose point is to be readable. Kept for runs
  that change something, since then each line says what it was before.
- **Failing the step on a pending extension.** 2026-09-17. It would abort `setup.sh` on every
  fresh machine over something no script can finish, and stop eight later steps for it.
- **Skipping `duti -s` when the readback already says the editor.** 2026-09-17. The readback is
  wider than the binding, so an extension it names as Zed may still have no binding of its own.
  Asking is cheap and idempotent, and the answer is what is read back, so the ask stays.

- **Declaring Zed as a dependency so the hardcoded step cannot fail.** 2026-09-24. The editor
  is a personal choice rather than something the repository needs, and declaring one would
  install an app on every machine whether or not it is wanted. Asking costs one Enter on a
  machine that is already set up.

- **Scanning `/Applications` Info.plists for `CFBundleTypeExtensions` to list the editors.**
  2026-09-25, measured on the second machine. Ten apps there could open a `.md` and the scan
  found two, because modern apps declare `LSItemContentTypes` instead, so Xcode, TextEdit and
  every browser were invisible to it. A list that under detects is worse than asking, since the
  person cannot tell it is incomplete.
- **A hardcoded list of known editors.** 2026-09-25. It goes stale with nothing reporting it,
  and the first draft already named an editor that has been discontinued.
- **A compiled Swift helper to ask Launch Services.** 2026-09-25. Proposed with a cache and a
  fallback to typing, so the step would survive a broken toolchain. JavaScript for Automation
  reaches the same `NSWorkspace` call through `osascript`, which the step already used, so the
  compiler, the cache and the fallback all bought nothing.
- **Remembering the chosen editor in a file on the machine.** 2026-09-25. Per machine state that
  can disagree with what Launch Services holds, when the binding already is the memory and a
  run on a machine already on the editor says one line.
  Corrected 2026-11-04 17:40, see the log entry of that date. The rejection still holds for a
  file on the machine. A row in `machines/` is tracked in the repository, and the disagreement
  it feared is now what the setup step reports.
- **Reapplying the current `.md` handler to every type when nobody can be asked.** 2026-09-25.
  That is guessing the answer, which is what the step was rebuilt to stop.

- **Ranking every app that can open the types by how many it opens.** 2026-09-25. On this
  machine Claude, Chrome, Helium and Notes open all seven probe types, tied with the editors,
  so the list put a chat app first. It stays only as the fallback for a macOS that drops the
  role query.
- **Taking the Editor role at its word for any one type.** 2026-09-25. Ghostty registers as an
  Editor of shell scripts so that double clicking one runs it, and it cannot edit anything.
  An app now has to edit more than half of the types.

- **Asking which editor on every setup run and applying the answer.** 2026-11-04. Any answer
  other than the current editor is forty dialogs, and a resetup is not the moment anybody chose
  to answer forty dialogs. The choice is a fact about a machine and now lives in its row, and
  applying it is its own command.
- **Confirming an apply by running the apply again.** 2026-11-04. Every type still pending is
  asked for again, so the check doubles the dialogs it was meant to count. `--check` reads only.

## Log

- **2026-09-17 15:40.** Set out to make the step say one line on a no-op run, since it printed
  a hundred and every other step printed one. Measured `duti -x` first, twelve milliseconds a
  call, bundle id on the third line, so reading it before every `-s` costs two seconds over the
  list.
- **2026-09-17 15:52.** Tested the change path by pointing `.log` at TextEdit with `duti -s` and
  running the step. The step said already, the readback said Zed, and `duti -s` had returned
  zero. Pointed `.md` at TextEdit the same way, same result. `NSWorkspace.setDefaultApplication`
  from a compiled Swift probe answered `userCanceledErr` for the same change and the handler
  stayed Zed. First reading was that macOS declines silently and duti swallows it.
- **2026-09-17 16:00.** Milos reported a dialog on his screen asking whether to keep Zed or
  switch `.log` to TextEdit, raised by the probes above. So the first reading was wrong in one
  word. macOS does not decline, it asks, and every call returns before the answer. The probes
  were answered keep Zed, so nothing on the machine changed. The script now reads the handler
  back after every call, reports pending for one still on its old handler, exits zero on it,
  and says one line when the run changed nothing and nothing waits. Verified on this machine,
  where the line reads thirty three already and sixty two untyped, in under two seconds.
- **2026-09-24 14:25.** A second machine without Zed failed this step, because it passed "Zed"
  unconditionally and nothing declared or installed Zed, so `set -e` stopped `setup.sh` there
  and every later step was skipped. `check-dependencies.sh` could not see it, since an app
  opened by name through `osascript` is not a command it looks for. The step now asks, as
  described under Now. Verified on this machine with a pseudo terminal, where an unknown name
  was refused and asked again and Enter kept Zed, and with no terminal, where it skipped with
  the note and exited zero.
- **2026-09-24 14:40.** Enter first kept the current editor. Milos asked for Enter to skip
  instead, so a manual run of `setup.sh` can pass the question by without changing anything.
  The current editor is still named in the question. Verified through `setup.sh`'s own stdin
  path, which it passes to every step untouched.
- **2026-09-25 10:30.** A Claude session on the second machine ran `setup.sh` with no terminal,
  so this step skipped with its note, and the editor it already knew had to be bound by hand.
  The note named only the interactive route, so nothing said the binder takes the name as an
  argument. The step now reads `MDJ_EDITOR`, offers a numbered list read from Launch Services,
  and `--list` prints it, and the root CLAUDE.md tells Claude to ask before a run. Verified on
  this machine. `--list` answered nine apps in under a second with Instruments left out as
  nested in Xcode, an unknown `MDJ_EDITOR` exited one, `MDJ_EDITOR=Zed` said its one line, no
  terminal and no variable noted and exited zero, and under a pseudo terminal an out of range
  number and an unknown name were refused and asked again, a number bound, and Enter and
  Ctrl D both skipped with exit zero. End of input used to stop the step with exit one under
  `set -e`, found by the same test.
  Corrected 2026-09-25 10:45, see the next entry.
- **2026-09-25 10:45.** Ctrl D as a skip was wrong. Milos wants it to stop, since Enter already
  passes the question by and a second way to skip leaves no way to abort. End of input now
  says the step stopped and exits one, so `setup.sh` stops there and its trap names the step.
  That is the behaviour the bare `read` had before, now with a line saying why. Verified under
  a pseudo terminal, Ctrl D exited one with the line and Enter still skipped with exit zero.
- **2026-09-25 11:05.** The first list ranked by how many probe types an app opens, which could
  not tell an editor from a viewer, since four viewers opened all seven. Launch Services keeps
  the role each app registered per type, and asking for Editors answered Zed, Xcode, VS Code
  and TextEdit for every type, plus Ghostty for shell scripts alone, which Milos pointed out is
  a terminal. The list now keeps Editors of more than half the types. Verified on this machine,
  `--list` answered those four in under a second, and with the role query forced absent the
  fallback answered the eight apps that open the types.
- **2026-11-04 17:40.** A resetup run by Claude passed `MDJ_EDITOR="Visual Studio Code"` on a
  machine whose handlers were on Zed, which raised forty dialogs, and Claude then ran the step
  again to confirm, which asked for every change a second time and raised forty more. Every
  handler read back as Zed afterwards. Milos asked for the editor to be separate from setup so
  a run never raises those dialogs. The editor is now the machine's `editor` row, defaulting to
  none, the setup step only reads and notes a difference, `set-dev-defaults.sh` applies the row
  when asked, and `--check` confirms by reading. `MDJ_EDITOR` and the per run prompt are gone.
  Verified on this machine with the row on `com.microsoft.VSCode`, where `--check` exited 3
  listing forty extensions on Zed, the setup step printed the count and the note and exited
  zero, a machine with no row said one line, and no dialog was raised by any of it.
