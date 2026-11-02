# Olm names, one word per part a person sees

Status. Settled by Milos on 2026-11-02, the words are in the Names section of `Spoons/Olm.spoon/AGENTS.md`, renamed through code, comments and docs on the olm-names branch, and held by the dry gate.

## Now

Every part a person sees has two kinds of name. A component is what it is on screen, chooser, input
field, list, row, selected row, preview pane, bottom bar with a left side and a right side, bar item,
info pane, actions pane, floating pane for either of those two, cheat sheet and toast. A concept is
what a part means, an action, something done to the selected row, and a shortcut, a key and what it
does. A bar item shows a shortcut and either runs an action or opens a floating pane, so it is
neither itself. The info pane is a list of shortcuts and the actions pane a list of actions.

The words are the code's words too. `previewPane`, `bottomBar`, `floatingPane`, `infoPane` and
`actionsPane` replaced `companion` and `dockedPane`, `footer`, `popover`, the key panel and
`actionPanel` in every identifier, file name, test and golden, `host/actionspane` is the host's
directory, the shared verbs are `showInfo` and `openActionsPane`, a manifest asks for a preview pane
with `surface.previewPane = true` and sizes it with `previewPaneWidth`, and the bar's things are
items in its own files. The left bar item reads Info. `row` stays the word in code and in
conversation, since a row is the same thing in all three lists. `test/drygate-names.lua` refuses
every retired word in every Lua, Swift and Markdown file of the spoon, comments included, apart
from the dated plans and briefs under `docs/`, which keep the words of their day, and a hyphenated
record name such as `docs/PLAN-ACTION-BAR.md`.

## Rejected

- **2026-11-02 11:00, keeping old identifiers in code that predates the names.** The first set of
  2026-10-29 said so, which left `companion` about 375 times and `footer` about 300 in the code
  while the docs said pane and bar, so a reader met two names for one part on every page.
- **2026-11-02 11:00, the first set's bare words, field, pane and bar.** Pane alone stopped naming
  one part once the two floating panes were panes too, and a bar with groups named keys and
  actions read as a third and fourth component. Each pane now says which it is, and the bar has a
  left side and a right side.
- **2026-11-02 11:00, shortcuts pane for the left floating pane.** It shows Olm's name and
  version and the leader legend beside the navigation keys, so info pane says what it is.
- **2026-11-02 11:00, button for a thing in the bottom bar.** Not a word Milos recognised for it,
  and a row is clickable too, so clickability names nothing. An element is named by the container
  it sits in, a row in a list and a bar item in the bottom bar.
- **2026-11-02 11:00, action for every thing in the bottom bar.** Only the Open bar item acts on
  the selected row, the other two open a floating pane, so calling all three actions gave action
  two meanings and made the actions pane sound redundant.
- **2026-11-02 11:00, item for a list's rows, renaming `row` in code.** `row` is about 5,400
  identifiers and part of the plugin contract, and `item` already means the data behind a row, so
  the rename would have merged two things under one name. Row reads right in all three lists.

## Log

2026-11-02 11:00, estimated, anchored to the conversation before the first commit of the branch.
Milos asked to settle the names of the chooser's parts, in code and in the rules. The first set
from 2026-10-29 was found to cover only some parts and to leave the code on the old words. Over
five rounds the components and concepts above were chosen, and the rejections listed were each
proposed and turned down in that conversation.

2026-11-02 14:30, estimated. The rename landed on the olm-names branch. A perl pass rewrote the
prose phrases first and the identifiers second, the files and directories were moved with git, the
manifest field and the bar's internals were renamed by hand, and camel case left in comments was
rewritten as words. The offline gates, every unit test of `suite.sh dry`, the swift pane build, the
dry gate and every golden, were green before and after. Two words the pass reached wrongly were
put back by hand, the report toast's bottom row, which is no bottom bar, and a partner StageManager
was meant to have, which is no preview pane. `docked panel` stays, since it is `CanvasPanel`'s
placement below an anchor and no part of the chooser.
