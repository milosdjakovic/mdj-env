# Olm colour roles

Status. Olm draws with exactly eight colour roles and nothing else. A plugin, a pane, a host or
a component names one of them, and a theme file answers exactly those eight.

## Now

The roles are foreground, subtext, background, border, highlight, primary, secondary and
tertiary. foreground is text you read, subtext is text you glance at, background fills every
panel, border is an outline, a divider and a graph baseline, and highlight is the bar under the
list cursor, the tint behind selected text in the field and the fill of a key chip. The three
accents are ranks, so a graph takes its series in that order, and they carry no meaning such as
success or error. A faded look is an alpha laid over a role, never a ninth colour.

The kit in `lib/ui/style.lua` resolves those eight and refuses any other colour name at build
time, so a retired word fails where it was written. A theme file under `config/themes` holds
the eight keys under `[dark]` and `[light]`. The Aura one is generated from the repository
palette, through `dotfiles/hammerspoon/theme-map`, which points each key at a role from
`theme/VOCABULARY`, border at dim and the three accents at primary, secondary and tertiary. The
default theme is hand written, its three accents a hand chosen purple, green and orange that
read on their own half's page. `.hammerspoon/AGENTS.md` carries the rule beside the one for
typography.

The merge from the fourteen names before it was path and meta into subtext, dim, overlay and the
faint baseline into border, surface into background, selection and badge into highlight, accent
into foreground, outline into border since it only draws the edge of the colour toast's swatch,
and note into an accent by rank or into subtext when it was text.

## Rejected

- **A larger set mirroring the whole repository vocabulary.** 2026-10-14. Carrying all sixteen
  roles of `theme/VOCABULARY` into Olm would give more names than Olm has uses for, and every
  name needs an answer in every theme and a decision from every plugin author about which one
  fits. Eight covers every surface Olm draws today.
- **Separate path, dim, surface and selection roles.** 2026-10-14. They were distinctions nobody
  could see. A path is read like any other glanced text, a dim rule and a divider are both a
  faint line, a surface was the background in every theme that shipped, and a selection tint and
  the cursor bar are never on screen in the same place at once.
- **Semantic accents such as success and error.** 2026-10-14. The palette never promised them,
  and `theme/VOCABULARY` already chose rank words for that reason. A role that means error has
  to be an answer in every palette, and Aura has no such colour to give.
- **All six Aura accents.** 2026-10-14. Rejected until a fourth has a use. Nothing in Olm draws
  more than three series, and an unused role is a name a theme must still answer.

## Log

### 2026-10-14 18:31

Decided with the person and built. The fourteen colour names the kit
carried were cut to the eight above, the theme files were rewritten to those keys, and every
reader moved. The two derived views for readers outside the kit, the chooser shaped one and
the surface shaped one, are kept and rebuilt from the eight roles, since the native provider,
the panel and speedtest's pane still read them. Speedtest's pane keeps its own four keys
inside the chooser shaped view until it is migrated to the kit. The Local Servers graph now
draws its CPU line in primary, its memory line in secondary and its baseline in border.
