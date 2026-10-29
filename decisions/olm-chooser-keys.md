# Olm chooser keys

Status. The default chooser's text field lets Hyper presses through to their own dispatch, the
action panel opens on Hyper and o in every list, with file search reveal on Hyper and f, and every
list carries an always visible action bar with a key panel on Command and ? and an optional
secondary on Command and Return. File search opens on Hyper and semicolon.

## Now

The default chooser's field event tap claims every key down so nothing reaches the app underneath, with
Escape answered first. The one exception is Hyper. The field takes an injected predicate,
`yields`, and a key it answers true for is passed on unclaimed. The composition root builds
that predicate over `owns` on every held leader in use, Hyper and META here, which its trigger
answers, since the phase A fix round of the list keys addendum in `olm-keymap.md`, so a key typed
under a held leader over a list never reaches the field and falls to that leader's one rule over
open lists. From phase 3 until then it asked only the one leader whose policy turned contexts on.
Since phase B the field also asks a list key watcher next, for a list chord with no held leader. Under the held trigger a key is the leader's
when it is the leader key or the leader is held, under the modifier trigger when its whole base
set is held. The field and the default provider know only that it is a
predicate, and the legacy provider needs nothing since its keys already reach Hyper.

The action panel is on Hyper and o in every list, declared once in `lib/surface.lua`, the loop
that once sat at the bottom of `config/keys.lua` having gone with that file. File search reveal in
Finder is on Hyper and f.

Every list in the default chooser carries one action bar row at the bottom of its own canvas,
always visible, since 2026-10-23, `Spoons/Olm.spoon/docs/PLAN-ACTION-BAR.md`. It replaced the
docked shortcut hint pane that showed after 800 ms with no key. The right side reads the primary's
label on Return, the secondary's on Command and Return when the list declares a `secondary`, and
Actions on the action panel's chord, each label following the level shown, the presentation's
`labels` first. A (?) button on the left carrying its key beside it, or the shared `showKeys` verb
on Command and ? and Command and slash, keys the list's field answers on no leader, spelled ⌘?, opens a
key panel over the bottom rows listing every other key, and any key that acts or a second click
closes it, Escape closing the panel and leaving the list. Command and Return in a list with no
secondary keeps choosing the row, and so does Command and keypad Enter, the secondary's second key.
Command and ? reaches a list only where the system's Show Help menu shortcut is off, which
`src/setup-macos-shortcuts.sh` sees to, `macos-shortcuts.md`. The legacy chooser has no field that
answers it and no key panel. File search opens on Hyper and semicolon, since macOS takes Hyper and
slash before any tap. While the action panel is open the bar describes the panel, and
every field key of the list is inert there. The action panel lists Back, the primary, the secondary and then
the verbs. The legacy chooser draws no bar.

The default chooser is the shipped default and the word chooser means it unless legacy is
named. The legacy chooser, the one wrapping hs.chooser, is deprecated, still selectable
through `chooser.provider` in the settings as a fallback, marked in its own header, and named
in a console warning on every load that picks it. Removing it is a later, separate step.

## Rejected

- **Hyper and slash for the key panel or for file search.** 2026-10-23. With Hyper as the four
  real modifiers from kanata, macOS takes Hyper and slash before any Hammerspoon tap or hotkey, so
  the key never arrives, and no setting was found that frees it.
- **Any Hyper key on punctuation where Hyper is the four modifiers, unless measured to arrive.**
  2026-10-23. Hyper and period is the system's own sysdiagnose shortcut and Hyper and slash never
  arrived, so the system reserves at least some four modifier punctuation chords with no switch.
  Hyper and semicolon was measured to arrive, which is why file search sits there.

- **A dropdown anchored to (?) for the key list.** 2026-10-23. It is a new kind of component with
  its own scroll and key handling, for a list of about a dozen keys.
  Corrected 2026-10-29. Under the swift chooser the key list is now exactly that, a glass popover
  above the keys group, since the same component serves the action panel too and the reason was
  a single user. `decisions/olm-swift-chooser.md` has it.
- **Turning the list itself into the key list the way Actions does.** 2026-10-23. The person loses
  sight of the list they were in.
- **The footer as a separate docked `CanvasPanel`.** 2026-10-23. A press outside the chooser's canvas
  hides the chooser, so (?) would need a second hit test across two surfaces, and one canvas draws
  both for free.
- **Keeping the pause before the footer shows.** 2026-10-23. What Return and Command and Return do is
  the thing worth seeing before pressing either, so the bar is there from the first frame.

- **Putting the action panel on Hyper and k.** 2026-10-14. k already moves the cursor up in
  every list, so two actions would answer to one key.
- **Having the field name HyperKey and ask it directly.** 2026-10-14. The field would then
  depend on one concrete trigger, and the field is the reusable part. A predicate injected from
  the root keeps the dependency pointing at a contract.

## Log

### 2026-10-14 20:00

Estimated time. Found that no Hyper binding fired while a canvas picker was open, so confirm,
move and the action panel were all dead there. The brief's decision six had the field claim
every key down, and Hyper's dispatch sits downstream of that tap, so the claimed press never
arrived. Hyper is now the one exception, passed through the injected `yields` predicate.

### 2026-10-14 20:00

Estimated time. The action panel moved from Hyper and period to Hyper and o at the person's
request, and file search reveal moved from o to f to make room. Reveal had been on f before it
moved to o for reading as open, and f now reads as Finder. The panel row, the hint strip and
the inventory golden follow from the declarations.

### 2026-10-14 21:00

Estimated time. The shortcut hint pane now shows after 250 ms with no key, down from three seconds,
at the person's request, and each key restarts that countdown. It stays up once shown until the list
closes. Hyper presses are yielded by the canvas field, so they never reach its key handler where
activity used to be counted. Activity is now counted in the canvas provider's selectNext, selectPrev
and insertSelected, which is what the Hyper dispatch calls, and not at the field's yield, since the
leader key autorepeats while held and counting there would keep the pane from ever appearing.

### 2026-10-14 21:20

The 250 ms delay above was tried live and works, and the person asked for 2500 ms instead, so
that is what ships. The 250 ms entry stands as the record of what was tried first. The debounce,
the latch and where activity is counted are unchanged.

### 2026-10-14 21:25

After living with 2500 ms the person asked for 1650 ms, so that is what ships now. Nothing else
about the pane changed.

### 2026-10-14 21:31

1650 ms still felt long, and the person asked for 1300 ms, which is what ships now.

### 2026-10-14 21:33

1300 ms still felt long, and the person asked for 800 ms, which is what ships now.

### 2026-10-14 21:45

The canvas picker becomes the default on main at the person's request, and the native picker is
deprecated rather than removed, kept as a fallback for now with a header note and a load warning.
An unknown provider name now falls back to canvas instead of native.

### 2026-10-14 22:30

Estimated time, anchored to the commit before this one.

The two pickers are renamed at the person's request. The canvas provider is now the default
chooser and the hs.chooser provider is now the legacy chooser. The files moved to
`lib/chooser/providers/default/` and `lib/chooser/providers/legacy.lua`, the facade registry
keys are `providers.default` and `providers.legacy`, and the `chooser.provider` setting takes
`default` or `legacy`. From here on the word chooser means the default chooser unless legacy is
named. The legacy chooser is still deprecated and still warns on every load that picks it. The
earlier entries above keep their old names, canvas and native, since they are records.

### 2026-10-14 23:00

Estimated time, anchored to the commit before this one.

The row boundary snap on keyboard movement is removed at the person's request. The list model
used to floor scrollTop to a whole row before checking the highlight, so one move up after
scrolling down past the visible rows realigned the viewport and sent the cut top row to the
bottom, and the first key after a wheel or trackpad scroll that stopped between rows snapped
the list. The viewport now moves only when the highlighted row is not fully inside it, and then
only far enough to show that row at the edge it crossed. A highlight already fully visible
leaves scrollTop exactly as it was. A wrap still jumps to its row under the same rule. No
Rejected item or earlier decision owned the snap, it was only written into the model's comments
and its offline case, both updated in this change.

### 2026-10-22 10:31

The field's yield followed list keys onto any leader, phase A of the list keys addendum in
`olm-keymap.md`. The root builds the predicate over `owns` on every held leader some list key
binds on, which is Hyper alone on this machine, so nothing a hand does here changes. A held leader
binding no list key is not asked, so a key typed with Right Option held over a list still reaches
the field. The harness word `leaderHeld` asks the same set.

### 2026-10-22 10:46

Corrected, the entry at 10:31 had the field yield only to held leaders some list key binds on, so
Right Option and a letter over a list still typed into the field. The coordinator decided, matching
what Milos asked of META over lists, that the field yields to every held leader in use, so META and
SUPER over a list are swallowed by the one rule like any key the open list does not bind.

### 2026-10-22 19:45

A list opened over a password field is deaf. With Hyper coming from kanata as real modifiers, the
launcher opened from a Safari password field, but nothing typed or chorded reached it, because the
default chooser never takes focus and reads keys through an event tap, and secure input hides every
key from every tap while the password field has focus. Two probes were run with Milos, each
triggered by a chord from inside the field. `hs.focus()` did nothing, Safari stayed in front and
secure input stayed on. A native `hs.chooser`, a real window that becomes key, took focus from
Safari, secure input went off within a tenth of a second, every letter typed reached its field, and
hiding it and activating Safari again put the focus and secure input back. So a list over a
password field can hear keys only if it opens as a key window for that time. Not built yet, since
never taking focus is the reason the canvas chooser exists, see `lib/chooser/providers/default/surface.lua`,
and taking it only while secure input is on is a design change of its own.

### 2026-10-22 22:37

Built. `lib/securefocus.lua` holds focus while secure input is on. It shows an empty native
`hs.chooser`, moves its window off screen, and answers a release that hides and deletes it and
activates the app that had focus. The default provider takes it as an injected `focusHold`, asked
after the surface shows and released after it hides and before `onClose`, so an insert on close
lands in that app, and a second show over a list already up keeps the hold it has. The root is the
only file naming it, and the provider names no mechanism. Normal opens are untouched, since the
hold answers nothing while secure input is off. The cost is stated in the lib's header. While a
list is open over a password field secure input is off, so any event tap on the machine could read
what is typed into that list, for as long as it is open. A borderless webview and `hs.focus()`
were both measured unable to take focus from Safari, so the native chooser is the one mechanism
proven, and a titled webview was never tried. With Hyper from kanata, Milos confirmed typing, list
keys, Escape, picking an app and inserting an emoji over a Safari password field, focus returning
to the field each time, and no change over an ordinary field.

### 2026-10-23 12:37

Return with a modifier is free for a list key. The provider's `uses` used to answer "Return
chooses the row" for Return and keypad Enter with any modifiers, so the keymap refused Command and
Return as a list chord, though nothing ever decided that it should. It was a side effect of
`_onFieldKey` reading the Return keycode alone. Milos wanted Command and Return for a secondary
action, so `uses` now claims only plain Return and plain keypad Enter. The field already asks the
list keys before `_onFieldKey`, so a list key on a modified Return answers first, and a modified
Return nothing claims still chooses the row as before.

### 2026-10-23 13:44

The docked shortcut hint pane is replaced by the action bar, `Spoons/Olm.spoon/docs/PLAN-ACTION-BAR.md`,
at Milos's request, built on `olm/action-bar` and waiting for its live load. `lib/hints.lua`'s
`footerModel` answers the bar's right side, the key panel's keys and one state string from the same
bindings, gates and labels `rowsFor` reads, and `footerFor`, `shortcutsContent` and
`shortcutPanelFor` are gone, footerFor folded into the model rather than kept beside it, since its
only readers were the pane and the tests. The default provider takes the model through a per
instance `config.footer` the stage passes on, draws it through `footer.lua` and the kit, polls it
four times a second while the list is up and owns the key panel's state and hit tests. The footer
height is the hint badge with the small space step above and below it. The stage answers the
current presentation's `labels` for the item last highlighted outside the action panel, and the
root asks it only for the context showing. Two shared verbs joined `keymap.listDefaults`,
`secondary` as the first field key default, a table of key, mods and leader false beside the bare
key names, and `showKeys` on slash. The `shortcutsPanel` policy, its commented seam in
`config/settings.lua` and `init.lua`, the per plugin panel triple in `lib/services.lua` and
`lib/wire.lua`, and the stage's three panel callbacks are removed. One reading of the plan was
chosen here rather than stated there, Escape over an open key panel closes the panel and leaves the
list, the way a popover answers it, and a second Escape closes the list.

### 2026-10-23 14:01

A review round on the action bar. While the action panel is open over a list the bar described the
list, its primary on Return, though Return then ran the highlighted panel verb, and Command and
Return would have run the list's secondary from inside the panel. Now `footerModel` takes the panel
row under the highlight from the root and labels Return with its title, or Run, offers no secondary,
and lists only the shared keys and Back. The list's field keys go inert while the panel is open,
through the watcher's own gate, each list predicate handed to `nav.fieldKeys` wrapped to answer
false while the panel is open, so the key falls through to the field and chooses the panel row.

The key panel closed only on the provider's own keys. It now closes before every handler in the
dispatch table through a new `onAction` hook on `nav.actions`, every action but `showKeys`, and on
a new query and a refresh from the top. A refresh that holds the row, a background answer arriving,
leaves it open. The held Escape that closes the panel no longer closes the list on its autorepeat,
and a scroll over the open panel moves nothing.

A shared binding's kind is now weak in `actionKinds`, so a secondary named like another list's
extra verb never hides that verb from its action panel and records no conflict. `chord = false`
on a secondary is refused, since the bar would name a key nothing binds. The secondary sits on
Command and keypad Enter as well as Command and Return, a list of places in `listDefaults`. The key
panel lists Back only where Backspace leaves a pushed level and the list lists no Backspace binding
of its own.

Known and left as it was, the same as the old pane. A tool's list hosted in the launcher shows the
launcher's words in the bar, since the showing context is the launcher's, and the action panel over
a hosted list omits the primary and the secondary unless the scope's verbs declare them.

### 2026-10-23 14:24

From Milos's first live test. The primary row in the action panel read Hyper I, a chord nobody
presses for it, so it now reads Return and the secondary Command and Return, and the key panel puts
Return in front of the primary's held chord. The primary and secondary rows had no icon while every
verb row had one, so a surface's `primary` and `secondary` may name an icon of the manifest, and a
list naming none takes Olm's own, `primary` on the return symbol and `secondary` on the command
symbol, declared in the action panel's manifest beside `back`, both names checked against AppKit
offline. The (?) button had no hover. It now draws its glyph alone at rest and the hint badge on
the highlight colour while the pointer is over it or its panel is open, the state a row takes under
the pointer, through the provider's one mouse tap.
Corrected 2026-10-23, see below.

### 2026-10-23 14:36

From Milos's second live check. The key panel spelled the primary as Return followed by its held
chord, Hyper and I. It now reads Return alone, the key a person presses, which replaces what the
entry at 14:24 said about putting Return in front of the held chord.

### 2026-10-23 14:39

At Milos's request the key panel's key is spelled Hyper and ? everywhere it is spelled, the key panel,
the OLM keys page and any surface reading the keymap's rows, while both Hyper and slash and Hyper,
Shift and slash open it. The leader's resolver already answers a list binding with no modifiers for
any modifiers held, so `showKeys` stays one catch all binding on slash and only its spelling
changed. Its place in `listDefaults` carries `shownMods` Shift, `hints.chordFor` and the keymap's
rows read it, and the shared glyph speller in `lib/cheatsheet.lua` folds Shift and slash into a
question mark, so no surface writes the character itself. A person moving `showKeys` replaces the
binding and its spelling, and freeing slash frees both presses, since they are one binding. The
action panel lists no row for it, being navigation, and no cheat sheet draws list keys.
Corrected 2026-10-23, see below.

### 2026-10-23 16:49

Measured live on this machine, macOS 27 with kanata, where Hyper arrives as the four real
modifiers, control, option, shift and command. A real Hyper and slash never reaches any
Hammerspoon event tap or hotkey, macOS takes it before the session taps. Hyper and period is
macOS's own sysdiagnose shortcut, so the system reserves at least some four modifier chords on
punctuation, and no setting frees them. Hyper and semicolon and Hyper and J do arrive. Command,
Shift and slash arrives once the system's symbolic hotkey 98, Show Help menu, is off, which was
done by hand here with `defaults write com.apple.symbolichotkeys` and `activateSettings -u`.

So, as Milos chose, `showKeys` moved to Command and ?, a field key on no leader, slash with Command
and Shift, answered by the open list's field like the secondary and spelled ⌘? by the shared glyph
speller. The Hyper and slash binding and the spelling trick of the entry at 14:39 are gone, and
with them the claim there that both Hyper and slash and Hyper, Shift and slash open the panel,
which no press on this machine ever could. File search's open key moved from Hyper and slash to
Hyper and semicolon, which nothing else claims, globally or in a list, and its typed alias in the
launcher stays slash and a space. `src/setup-macos-shortcuts.sh` turns symbolic hotkey 98 off
where the hammerspoon piece is on, `macos-shortcuts.md`.

### 2026-10-23 17:13

From Milos's live check. The (?) button now carries its key beside it as a badge, the way Actions
carries Hyper and O, spelled by the shared speller from the first key `showKeys` sits on, moving
with a person's chord and absent when both keys are freed, and the glyph and the badge light under
the pointer and answer a click as one button. `showKeys` also answers Command and slash, a second
field key place beside Command and ?, the way the secondary sits on Return and keypad Enter, and
both are listed once as ⌘?. Freeing one key leaves the other bound and shown.

### 2026-10-23 17:33

From Milos. A button reading ? and then ⌘? was confusing, so the ? glyph gave way to an icon, the
outline keyboard SF Symbol with a keyboard emoji as its fallback, declared as Olm's own `keys` icon
in the action panel's manifest beside `primary` and `secondary` and drawn through the icon engine
the provider is already handed. The kit gained an icon size for it, `hint`, derived from the line a
hint badge's glyph sits on. The ⌘? badge stays beside the icon, and one highlight now spans both
when the button is lit, with the hit area covering both.

### 2026-10-23 17:59

Milos decided the type sizes. Nothing in Olm is drawn at 12 points any more, so the section role
ships at 14, in `config/typography.toml` and in the kit's own fallback, which moves the action bar's
key badges, the cheat sheet section titles and the pane headings from 12 to 14. The bar's labels and
the key panel's go back from body to caption, 14, by his choice, which overrides the rule that a
hint label is body, so the rule now names a hint label caption, in the hammerspoon `AGENTS.md`
typography section. The bar grows to 35 points, the 23 point hint badge with the small space above
and below, and a key panel row to 23, both from the tokens.

### 2026-10-27 15:30

Bug found, and a belief from 2026-10-22 22:37 corrected. That entry measured secure input going off
within a tenth of a second once `lib/securefocus.lua`'s native chooser became key, and that holds
only for an app that drops secure input when it loses focus, as Safari did. Chrome can keep it with
no window in front. At 15:27 secure input was on, `kCGSSessionSecureInputPID` named Chrome, and
Ghostty was frontmost. Opened over that, the clipboard list showed, the hold put its empty native
chooser in front, the field's tap stayed blind, and Up, Down, Return and Escape went to the native
chooser instead, which the console records as `unable to select row -2 of 0` at 15:20:55 and twice
at 15:26:09. Nothing is changed yet. The list was deaf before the hold existed in this case too,
since no tap can hear keys while another process holds secure input.

### 2026-10-27 16:45

Measured with Milos, a passive watcher logging secure input, the frontmost app and the focused
window every half second. Over Chrome's password field on the w3schools tryit page the hold's
chooser became the focused window and Chrome stayed the active application, secure input on and
the tap hearing nothing. Calling `hs.focus()` and focusing the chooser's window after the show was
tried, and it made Hammerspoon the active application, and secure input still stayed on, the tap
still deaf, until Milos left Chrome. Over Safari's the same hold made Hammerspoon active and secure
input went off, as on 2026-10-22. So Chrome keeps secure input for as long as its field has focus
inside its own window, whichever application is active, and no way of taking focus can end it.
The focus change was reverted, since it fixed nothing. A list over a Chrome password field can only
hear keys by a route secure input does not hide, which `hs.hotkey` is, Hyper's keys acting there
throughout.

### 2026-10-27 16:58

Built, the route the 16:45 entry named. While secure input stays on after the hold's chooser is
key, `lib/securefocus.lua` relays into the list what the tap cannot hear. The chooser's typed text
goes to the field's text, and Up, Down, Return, keypad Enter, Escape, Command and Return, Command
and a digit, Command and ? and, while the text is empty, Backspace are claimed through `hs.hotkey`
and handed to the field as key events through `Field:feed`, so each takes a tapped key's own path,
the field's yield, the list key watcher and its keymap. The relay polls secure input every tenth of
a second and claims nothing while it is off, since a key a tap hears and a hotkey fires on would act
twice, which the 15:40 probe measured, both seeing every key with secure input off. Tinycast's
palette was read for comparison, `PalettePanel.swift`, a borderless non activating panel that
becomes key and reads every key as a window event, which is why it never meets this. Milos
confirmed searching, moving, Backspace, Return and Escape in the clipboard over Chrome's password
field with secure input on for the whole run, and over Safari's. A list key a list binds with no
leader beyond those, a person's own `ctrl+j`, is not relayed, and is the gap left.

### 2026-10-27 18:40

The relay's two gaps closed. Text the list writes into its own field, a scope's word after an
alias directory row or a seeded query, never passed through the hold's chooser, so the next letter
typed there replaced the field with that letter and left the scope. The hold now answers a mirror
beside its release, which the provider tells the field's text on every change, writing it into
the chooser with the caret moved after it through the accessibility tree, since `hs.chooser:query`
leaves what it wrote selected. Milos confirmed it over Chrome's password field, `?` and a space,
the VPN row, then a letter, which stayed in the VPN list. And the list keys a person binds with no
leader are relayed too, the root handing the hold every field key as a modifier set and a keycode,
with a combination the fixed set already claims claimed once. No such key is bound on this machine,
so that half is pinned by `test/securefocus.lua` alone.
