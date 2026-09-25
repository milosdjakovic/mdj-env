# Default editor for development files, and what a script can and cannot do about it

Status. `src/set-dev-defaults.sh` asks Launch Services to bind every listed extension to the
editor, reports by reading the handler back rather than by trusting duti's exit code, and says
one line when nothing changed. On macOS 27 a change is a dialog the person answers, not a call.

## Now

`setup-dev-defaults.sh` takes the editor from `MDJ_EDITOR` when it is set, which is how a run
with no terminal is answered, since an agent can ask before `setup.sh` starts but not during
it. Otherwise it asks which app should open development files, as a numbered list of the apps
Launch Services has registered as an Editor of more than half of a handful of development
types, ranked by how many each edits and marking the one that opens `.md` now. The role query
is deprecated since macOS 12 with no replacement that keeps the role, so when it answers
nothing the list falls back to every app that can open the types. A number or a typed name answers it, and
`--list` prints the same list one name per line, so the prompt and anyone asking before a run
read one answer. The list is read through `osascript` and JavaScript for Automation, which
needs no compiler. Enter skips, and so does a run with no terminal and no
variable, each with a note that `setup.sh` repeats at the end and that names
`set-dev-defaults.sh "App Name"` as the route that needs no terminal. The script asks
`duti -s` for every extension in its list, then reads the handler back with `duti -x`, and the
readback is the report. An extension already on Zed is counted as already, one that moved is
counted as changed, one whose extension resolves to an invented `dyn.` type is counted as
untyped, since Launch Services will not bind a handler to those, and one still on its old
handler after the call is counted as pending. On a run where nothing changed and nothing is
pending the step prints one line, the same shape every other idempotent step in `setup.sh`
uses, and prints the full listing only when there is something in it to read.

Pending is the case that matters and it is not a failure. On macOS 27, changing the default
handler of a type raises a dialog, naming the application that has the type and the one
asking for it, and the person chooses. `duti -s` returns zero the moment it has asked, before
the dialog is answered, so a script cannot know the outcome and cannot influence it. A fresh
machine where Zed is not yet the default will therefore raise one dialog per typed extension,
up to thirty three of them, on the first run, and the step says so and asks for a second run to
confirm. That is macOS's design, the same guard that already kept `.html` out of the list
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
- **Reapplying the current `.md` handler to every type when nobody can be asked.** 2026-09-25.
  That is guessing the answer, which is what the step was rebuilt to stop.

- **Ranking every app that can open the types by how many it opens.** 2026-09-25. On this
  machine Claude, Chrome, Helium and Notes open all seven probe types, tied with the editors,
  so the list put a chat app first. It stays only as the fallback for a macOS that drops the
  role query.
- **Taking the Editor role at its word for any one type.** 2026-09-25. Ghostty registers as an
  Editor of shell scripts so that double clicking one runs it, and it cannot edit anything.
  An app now has to edit more than half of the types.

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
