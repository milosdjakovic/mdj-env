# Herdr theme

Status. Aura expressed in herdr's own tokens on both appearances, with `terminal` kept as the
base. The faint agent line was a render attribute and never a colour.

## Now

Herdr's eighteen built in themes are compiled into the binary and there is no way to add a
nineteenth, so `[theme.custom.dark]` and `[theme.custom.light]` in `config.toml` are a full
override set with `terminal` as the base, and anything not named falls back to the palette
Ghostty is painting. Herdr's token names are Catppuccin's vocabulary, so a theme is that
vocabulary filled from Aura's ramp. The light values are derived from Aura's own proportions,
with four places overruled on purpose by looking at the screen. `sidebar_bg` is deliberately
absent. The agent rows restate two entries with `dim = false`. All of it is commented in place
in the config.

## Rejected

- **Hunting for the token that painted the faint agent line.** 2026-09-13, two rounds before
  7c722f1. Both lines already read `overlay0`. The difference was crossterm's SGR 2, the
  terminal's own faint attribute drawn at Ghostty's faint opacity, and no value on any token
  could ever have levelled it. Two rounds of reasoning were both wrong for the same reason, the
  premise that a visible difference means a different token.
- **Restating fourteen tokens per appearance.** 2026-09-13, before f5d9ff7. Eleven had a palette
  source sitting right there. Restating them pinned herdr to one Aura variant, so a soft text
  palette would have muted the terminal while herdr kept shouting.
- **`sidebar_bg` set to the ramp's mantle.** 2026-09-13, before ee10ac8. Correct on the dark
  half and inverted on the light one, since mantle sits below the background and the light ramp
  runs downward, so the same offset lifted it.
- **Aura's purple `#a277ff` for `mauve`.** 2026-09-13, ee10ac8. It made one secondary line the
  only secondary text on the page in a different colour. One line from here if wanted.

## Log

### 2026-09-13 10:25

d776ad9. The terminal palette keeps painting everything made of text, and the few surfaces it
cannot describe are lifted from each theme's own interface specification rather than invented.
Herdr reached for slot 8 on the focused row, the comment grey, which under Aura is a light slab
on a near black page and was what made the chrome look broken under every theme tried.

### 2026-09-13 10:52

f5d9ff7. The overrides shrink to the three surfaces a palette cannot describe, which is what
lets one config serve all four Aura variants.

### 2026-09-13 12:19

ee10ac8. Aura in herdr's own tokens on both appearances. The finding that made it possible is
that herdr's token names are Catppuccin's vocabulary, proved by the default config filling each
token with the matching Catppuccin value. The light half is derived with Aura's own proportions,
checked against Catppuccin Latte and Mocha holding theirs across the switch.

### 2026-09-13 12:47

7c722f1. The agent name stops being dimmer than the branch it sits level with, which was never
a colour problem. Same token, one carries a dim render attribute.

### 2026-09-13 12:57

921fbe5. The tab name beside an agent's workspace stops being faint, same cause, and the reason
is written down once for all three places it showed up. Which entry was the faded one came from
`herdr api snapshot` rather than from looking.
