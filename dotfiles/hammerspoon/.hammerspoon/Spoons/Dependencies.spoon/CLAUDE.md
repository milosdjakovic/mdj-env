# Dependencies.spoon

The one door to an external tool, and the only thing in this config that probes
for one. The cross cutting rules, how a declaration travels upward and where the
install mapping lives, are in the hammerspoon `CLAUDE.md`. This file keeps the
decisions inside the spoon.

## Why a door rather than a checker

The guarantee comes from the code path, not from remembering to run something. A
spoon asks its injected adapter for a tool by name, the adapter answers only for
what that spoon declared, and an undeclared ask returns nothing and names the
spoon in the console. So an undeclared dependency stops working on the machine of
whoever is writing it. That inverts the usual failure, where the author's machine
happens to have the tool and only the next machine breaks. A checker was
considered as the primary mechanism and rejected for exactly that reason, it
catches the problem later and only if run. The reconciler one layer up still
exists, but it covers what a door structurally cannot see, whether the tool was
ever mapped to an install and whether code went around the door.

## Why the probing is one pass, and why that made this cheaper

Four spoons each ran their own `command -v` through a login shell, which is tens
of milliseconds each. Every path kind tool now goes through a single shell call
built once from the whole declared set, and the other three kinds resolve in
process, a file test and a bundle id lookup. So this is one shell spawn no matter
how many tools are declared, which is fewer than before. That matters because the
usual objection to a dependency layer is that it costs load time, and here it
removes some.

## Four kinds, because the config already needed all four

A `path` tool is a binary on the login PATH. A `system` tool is a binary at a
fixed absolute path from macOS or the Xcode command line tools. An `app` is a
macOS application with no binary anywhere, probed by bundle id. A `manual` tool
is installed by a clone or a script, so it declares a marker path to test. A
`core` kind is recognised too, and deliberately skipped, since it names a
capability the root resolves at wiring time, and this file has no cause to
probe for it.

The set is not speculative. Capture has one provider backed by a binary and
another backed by an application checked by bundle id, so a binary only model
would have silently excluded half of that spoon from the whole scheme. The system
kind exists for a second reason too, it lets the reconciler tell a legitimate
fixed path from a hardcoded Homebrew one, which is what makes its bypass check
possible without false alarms.

## Where a declaration goes, and why the owner is not the scope

A declaration sits beside whatever knows the tool. `dependencies` at a spoon root
declares needs of the whole spoon, which is right when the spoon's own `init.lua`
runs the tool. `<base>.dependencies` declares needs of its sibling `<base>.lua`,
which is right whenever one inner file is the only one that knows the tool exists,
so a provider carries its own contract and a new backend is a new file plus a new
declaration with nothing shared to edit. Both names are found anywhere under a
spoon, by a depth capped walk.

The adapter is still keyed by spoon, not by file, and that split is deliberate.
The spoon root is what the composition root calls `scope(name)` for, and it is what
hands a resolved path to its own providers, so a per file scope would need an
injection point per file and there is none. Placement therefore decides which file
owns a line and the spoon still decides who may ask for it. The owner label rides
along on the entry for the console, the report, and the generated manifest, which
is what makes a missing tool read `Capture/macshot` rather than `Capture`. A
`Capture` scope answering for a tool `macocr.dependencies` declared is correct, both
providers belong to that spoon, and the label is what tells you which one went dark.

Two readers apply this rule, this spoon at load and `dependencies-collect` when it
generates the manifest. They are kept identical on purpose, because a file only one
of them found would be either invisible at runtime or missing from the contract
with the layer above, and both failures are silent.

## Where the line is drawn on what to declare

Declare a tool when its absence is credible. The macOS built ins this config also
uses, `sips`, `open`, and `head`, are not declared, because they ship with every
install and listing them would be noise that makes the real declarations harder
to read. The Xcode command line tools are genuinely optional on a fresh machine,
so `swiftc` is declared. This is a judgment rule rather than a mechanical one, and
it is written down here so it stays consistent.

`perl` is the one apparent exception, declared even though macOS ships it. It is
declared because the file that needs it is a shell script run by hand outside
Hammerspoon, so the declaration is the only record that the script needs it at all,
and the map answers plainly that it comes with the system. A tool worth naming in a
script's own guard is worth naming in that script's declaration.

Maintenance only needs are declared too, and always as `optional`. `Emoji` needs
`jq`, `perl`, and `hs` to rebuild its vendored dataset, and needs none of them to
run, since the dataset is committed. Declaring them puts the requirement in the one
place the layer above reads, and optional is what keeps a missing one from costing a
spoon that works fine without it.

## Two policies, and why required is rare

`optional` means the feature, or one backend of it, is quietly excluded, with one
console line saying what was dropped. `required` means the root refuses to wire
the spoon at all. Required is reserved for a spoon that is nothing but a front end
onto its tool, where a present but dead surface would be worse than no surface,
which today is only `Convert`. `Eyedropper` was written as required first and
changed to optional on the same reasoning, because it already answers a failed
build with an alert and a log line and its key stays worth discovering. The
distinction is about what the user sees, not about how badly the spoon needs the
tool.

## The adapter is per consumer, on purpose

`scope(consumer)` hands back a small dot called table rather than the registry.
A spoon can therefore reach only what it declared, cannot enumerate other spoons'
tools, and cannot learn that a registry exists. `satisfied()` is on that adapter
so the root can decide whether to wire a spoon at all, which is what turns the
required policy into real behaviour rather than a label.

## What it deliberately does not do

It never says how to install anything, because that mapping lives one layer above
the whole config and pointing at it from here would be the leak this work removed
in three places. It does not re-probe while Hammerspoon runs, since installing a
tool mid session is rare and a reload re-probes anyway, so a consumer needing a
genuinely live check keeps its own, which is why the macshot provider still checks
the URL scheme and the running process itself and asks the adapter only whether
the app is installed. It does not validate that a resolved binary works, only that
it is there.

## What would break if the shape changed

Making the adapter answer for any tool rather than only declared ones would
remove the entire guarantee and leave nothing but the reconciler. Probing lazily
per call rather than once at load would reintroduce the per consumer shell cost
this replaced and lose the single summary line. Letting a declaration carry an
install hint would put package manager knowledge back inside a spoon, which is the
one thing the layering forbids.
