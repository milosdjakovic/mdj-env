# Olm chooser row limit, and the row of more

Status. On the canvas-glass-layout branch, both choosers show 50 rows of any list by default and end a longer one in a row that adds the next 50.

## Now

`chooser.rowLimit` in `config/settings.lua`, 50 as shipped, is the most rows a list shows when its
presentation names no `rowLimit` of its own. A presentation's own number wins, emoji's 100 and
the clipboard's and FileSearch's 200, and `false` opts a list out. The cut is `lib/chooser/rank.lua`
after ranking, so a search still finds the best rows among every one, and pinned and fromQuery rows
are never cut. `rank.apply` answers what it cut as a third value, and the engine ends the list
there in a row of more, Show 27 more, with 77 more in all beside it when more than a page is left.
It carries the ellipsis icon, `more` in the action panel's manifest, handed to the engine as
`{ icon, owner }` the way the bar's keys icon is, and no item. Choosing it, by Return, a press or a digit, ranks in the next page and lands the
highlight on the first row it added, and a new query, a show or a refresh from row one is one page
again. A right press on it reaches nobody. Each view draws it its own way, the canvas view in the
subtext colour with no icon.

The engine is shared, so the behaviour is one piece of code under both choosers. Each provider
loads its own copy of the engine module, which is why the default reaches it through the
provider's `configure`, and both are handed it since 2026-10-30. The swift view hands the row to
its library with `muted` set, and `native/List.swift` draws a muted title in the subtext colour.

A launcher query scoped to a plugin is ranked and cut by `host/queryscope` at the scope's own
limit before the engine sees it, so the row of more there reaches that limit and not past it.

## Rejected

- **2026-10-30, a count drawn under the list instead of a row.** Asked for first as a line saying
  how many more results there are. A row is something a person can reach with the arrows and
  choose, it needs nothing new from either view's drawing, and the swift chooser gets it from the
  engine with no native change.
- **2026-10-30, the row of more adding every remaining row.** A list of thousands, the clipboard
  history or the emoji set, would then build and style every row at once, the cost `rowLimit` was
  introduced to avoid. It adds one page at a time.
- **2026-10-30, opting the long lists out up front.** Browser tabs and processes were the
  candidates. The row of more leaves nothing out of reach, so no list was opted out, and `false`
  stays for a list that turns out to need every row at once.

## Log

### 2026-10-30 20:32

Built for the canvas chooser on the canvas-glass-layout branch. `rank.apply` reports what it cut,
the engine reads the default from `configure` and adds and answers the row of more, the registrar
accepts `rowLimit = false`, and the canvas view draws the row in the subtext colour. The dry suite
passes with `test/rowlimit.lua` added, and every unit case passes, `test/cases/stage-search.lua`
now expecting the row of more after a list its limit of three cut. Not yet seen live.

### 2026-10-30 20:35

The swift chooser takes the same default, handed through its provider's `configure` from the root,
and draws the row of more in the subtext colour through a new `muted` field on the native row. The
engine code is the one both choosers already shared, so nothing else moved. The dry suite passes,
`swiftpane` compiling the changed sources, and every unit case passes. Not yet seen live.

### 2026-10-30 21:20

Seen live on the canvas chooser, and the row of more wanted an icon, an ellipsis. It is the `more`
icon in the action panel's manifest, SF `ellipsis` with `…` for the emoji set, handed to both
providers by the root once the plan names the action panel's identity, so the engine names no
owner. Every row draws its icon the way the rest do, the canvas through list render and swift
through the icons it resolves for the rows near the viewport.

