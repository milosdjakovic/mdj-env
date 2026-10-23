# Setup grants, and how a run takes a person to each one

Status. `src/setup-grants.sh` walks every declared grant near the end of `setup.sh`, and with a
terminal it opens the pane of each required grant still missing, shows the program to add when
there is one, and waits for it, while `setup.sh` asks for the password once for the whole run.

## Now

A grant is the one kind of dependency no script can give, so a fresh machine always needs a
person for it. What a script can do is take the person to the exact row at the moment the grant
can be given and notice when it is given, so nothing is hunted for and no second run is needed
to confirm it. That is the whole of the step.

It runs after every step that installs or starts something a grant applies to and before the
reconciler, so the reconciler reads the grants as they now are. It walks the grants the way the
reconciler does, finding each module's manifest and its `grants-probe` by name, skipping a
module this machine switched off, and names no module. The mechanism is `src/lib/grants.sh`, an
engine over the probe contract, where each module's probe is the strategy for its own grants and
the step is the composition root that decides whether a person is there. `src/setup-kanata.sh`
calls the step for kanata alone when it runs on its own, and inside `setup.sh` it leaves its
grants to the step, which `MDJ_GRANTS_LATER` tells it, so a person meets each grant once.

With a terminal, a required grant that is not given gets one line saying what to do, taken from
the map, its pane opened once, its program revealed in Finder when one has to be dragged into the
list, and a wait of up to three minutes that asks the probe every two seconds and ends on Enter.
A refused grant says that macOS never asks again and still opens the pane, since the pane is the
only way back. A grant the probe cannot answer gets twenty seconds first, since what was just
started is usually still on its way to its checks, and then a note. Without a terminal nothing
opens, and every grant not given is a closing note, which is what a run said before. An optional
grant is only ever a note, because the module runs without it and whether it is wanted is the
person's choice, which a run that stops for it would be making for them.

The pane is a fact about where a grant is given, so it lives in `DEPENDENCIES.map`, as a fourth
field that only grant rows carry, an `x-apple.systempreferences` address beside the sentence a
person reads. The reconciler reports a grant row without one and any other row with one. The
program to act on is a fact about the module, so the module's probe answers it, through a second
verb, `grants-probe --subject LOCATOR`, which prints `file PATH`, `app BUNDLE_ID` or nothing. The
kanata probe reads the program from launchd, which has it from the plist its step wrote, and the
Hammerspoon probe reads the bundle id from its module's own declaration of the application, so
neither path is written twice. A probe without the verb answers it as an unknown locator, which
reads as no subject.

Setup never launched Hammerspoon, and its probe can only answer while Hammerspoon runs, so on a
fresh machine its Accessibility grant could only ever be a note. The `app` subject answers that
without the step knowing the module. When a probe cannot answer and its subject is an
application, the step opens the application, with a terminal only, and gives it the twenty
seconds to start and answer. Hammerspoon then asks for Accessibility itself, macOS lists it, and
the grant is guided like any other.

The password is asked once. With a terminal, `setup.sh` runs `sudo -v` before the first step and
a background loop refreshes the timestamp every fifty seconds until the run ends, when the exit
trap stops the loop and drops the timestamp. Every later sudo in the run, a step's own or
Homebrew's, finds it valid. The kanata step and the command line tools step check with `sudo -n`
before asking, and they now go ahead where they would have asked, which is the same work one
prompt earlier. Without a terminal nothing about sudo changes.

## Rejected

- **Opening every pane at once, up front.** 2026-10-23. System Settings is one window, so each
  address replaces the last and only the final pane is left showing. Most grants also cannot be
  given that early, since the kanata binary is not copied, the driver not installed and
  Hammerspoon not running until later steps have run, and a pane for a program that does not
  exist yet has nothing in it to switch on.
- **Clicking a grant from a script.** 2026-10-23. Nothing a script can run gives one. `tccutil`
  only resets, the TCC database is protected by System Integrity Protection, and scripting the
  System Settings window would need Accessibility for the terminal, which is the same kind of
  grant. A configuration profile from device management is the only route macOS offers, a
  personal machine has none, and even a profile is documented as only letting a person approve
  Input Monitoring rather than giving it.
- **The pane address inside the probe, as another verb.** 2026-10-23. The probe is written to stay
  ignorant of System Settings, and the map already says where every dependency comes from,
  grants included, in prose. Putting the address beside that prose keeps one fact in one place.
- **The pane address inside the prose, as a `pane=` word in the detail.** 2026-10-23. A sentence
  with data inside it has to be parsed out of the sentence, and a check of its shape has to find
  it first. A fourth field is one field to read and one to check, and the sentence stays a
  sentence.
- **Reading the driver pane from `systemextensionsctl list`, as `setup-kanata.sh` did.**
  2026-10-23. The listing gives a sentence, not an address, so it could be printed but never
  opened. Apple moving a pane is the same risk for all five grants, and the map is the one place
  each is fixed.
- **The subject as an optional field in the grant declaration.** 2026-10-23. Hammerspoon's
  declarations are generated from plugin manifests in Lua and from a hand written module file,
  so a new column means a change to the collector, both formats and the reconciler, for a fact two
  of five grants have. It would also write the kanata binary's path a second time beside the one
  `setup-kanata.sh` installs to. The probe verb lets each module read the subject from where it
  already lives.
- **A setup step that opens Hammerspoon by name.** 2026-10-23. It would name one module in the
  run for what the `app` subject already says for any module. Opening it without a terminal was
  turned down too, since nobody is there to answer its prompt and the grant is only a note then.
- **Guiding optional grants.** 2026-10-23. Each stops the run for a feature the person may not
  want, Location Services for the wifi names say, and the note already says what to do.
- **An unbounded wait.** 2026-10-23. A run left alone would wait forever on the first grant. Three
  minutes is enough for a few clicks and a password, and past that the closing notes carry it.
- **A sudoers rule, or a password kept for an askpass helper.** 2026-10-23. Both change how the
  machine treats root, or keep a password, for a setup convenience. A timestamp that ends with
  the run changes nothing after it.

## Log

### 2026-10-23 11:13

Built on `setup/guided-grants`. The step, the library, the `--subject` verb in both probes, the
fourth map field and its check, and the one password in `setup.sh`. The pane prose
`setup-kanata.sh` printed for the driver and the note it left for the two binary grants are gone,
and its grants section now calls the step for kanata or leaves it to the run.

Which addresses were seen to work. The Accessibility address was opened on macOS 27 when kanata
was first set up, `decisions/kanata.md` has it. The other three were found rather than opened,
since this change was built where System Settings could not be opened. `Privacy_ListenEvent` and
`Privacy_LocationServices` are anchors in the search terms of macOS 27's
`SecurityPrivacyExtension.appex`, the bundle `com.apple.preference.security` opens, beside
`Privacy_Accessibility`. `ExtensionItems` is the only anchor in `LoginItems.appex`, whose bundle id
is `com.apple.LoginItems-Settings.extension` and whose settings declare that it accepts the
`x-apple.systempreferences` scheme, and it opens the Extensions part of Login Items and
Extensions, where Driver Extensions is one more click. The first fresh machine confirms all three.

A scratch harness with fake modules, stubbed probes, a stubbed `open`, a stubbed `src/machine.sh`
and a real pseudo terminal passed every case. Every grant given opened nothing and left no note. A
required grant not determined until the third poll opened its pane once, revealed its file and
went on with no note. One never given stopped at the bound and left a note. Enter ended the wait
at once and left a note. A refused one said macOS never asks again and opened the pane. One that
could not answer twice and then did opened its application and needed nothing more, and one that
never answered left a note after the short wait. With no terminal nothing opened and each grant
was a note. An optional grant with a terminal was a note only, and a module switched off was never
probed. The sudo loop was tested apart with a stubbed sudo, asking once, refreshing, and dropping
the timestamp at exit, and doing nothing without a terminal.

The bash macOS ships, 3.2, answers a timed out `read` with the same status as the end of input,
where later versions answer above 128, so the first version of the wait took every timeout for a
closed terminal and stopped listening for Enter. The wait now tells the two apart by whether any
time passed.

On this machine, where every grant is given, the step said all five were given and opened nothing,
with and without a terminal, and for kanata alone said all three.

### 2026-10-23 11:22

The three pane addresses found inside macOS 27 were opened on this machine and the window System
Settings showed was read back through System Events. Privacy_ListenEvent opened Input Monitoring
and Privacy_LocationServices opened Location Services. The LoginItems address opened the window
titled Login Items, the Login Items and Extensions page, from which Driver Extensions is one more
click, as the map's sentence for that grant says. All four addresses in the map have now been
opened at least once.
