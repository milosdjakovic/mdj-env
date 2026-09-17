# Default editor for development files, and what a script can and cannot do about it

Status. `src/set-dev-defaults.sh` asks Launch Services to bind every listed extension to the
editor, reports by reading the handler back rather than by trusting duti's exit code, and says
one line when nothing changed. On macOS 27 a change is a dialog the person answers, not a call.

## Now

`setup-dev-defaults.sh` runs `set-dev-defaults.sh "Zed"` on every setup. The script asks
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
