# Ghostty theme and the Aura pairing

Status. Aura on both halves, the light half derived, all four upstream variants carried.

## Now

Ghostty takes a light and dark pair on the theme key and reads the desktop appearance itself,
so no watcher is needed. Aura Dark answers dark and Aura Light answers light, and Aura Light is
derived arithmetically from Aura Dark because upstream publishes no light edition. The file
carries the method so it can be rerun or argued with. Aura is ported from its palette table
rather than from any terminal package, which is what restored pink and blue, since the package
repeated purple across two slots and green across two more. The four variants, plain, soft
dark, soft text and both, are carried under their upstream names.

## Rejected

- **Catppuccin Latte and Mocha.** 2026-09-11 16:12, f49b8f0, replaced 2026-09-12. They shipped
  inside Ghostty, which left the stowed themes directory holding two owls nothing pointed at.
- **Night Owl and Light Owl on the two halves.** 2026-09-12 16:55, 426d1b4, replaced eight
  minutes later. A tidy argument about file ownership rather than a judgement about how a
  terminal reads. Under a real toggle Aura's near black held up better than Night Owl's navy.
- **`aura.theme` beside `aura`.** 2026-09-12 16:55, c5b5add. Same palette, but a comment after
  every value, and Ghostty only reads a comment that owns its own line, so `validate-config`
  rejected it with exit 1. The duplicate was the broken half.
- **Aura's own terminal package as the source.** 2026-09-13 10:25, 13bab8e. Four chromatic
  accents where the theme names six, so two colours could never be reached on screen, which is
  why blue was a colour that could not be found while probing herdr.

## Log

### 2026-09-11 16:12

f49b8f0. The terminal follows the appearance for the first time, Catppuccin pair, proved
against `validate-config` because a wrong name fails quietly at load.

### 2026-09-12 16:55

426d1b4 and c5b5add. Owls replace Catppuccin, the broken Aura duplicate goes.

### 2026-09-12 17:03

73a1ea4. Aura takes the dark half back, Light Owl keeps light. Looked at rather than reasoned
about.

### 2026-09-13 10:25

13bab8e, 3902765. Aura from its palette table, all four variants carried.

### 2026-09-13 12:09

48f02c1. Aura Light derived, both halves the same theme.

### 2026-09-13 12:33 and 13:49

b234bd4, f532aa8. Neovim follows the same switch, the last layer still pinned to dark and pinned
twice over, then follows it while running rather than only at startup.
