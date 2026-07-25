---
name: html-reports
description: Build any standalone HTML report, analysis writeup, findings document, briefing, or single self contained .html page in Milos's preferred visual style. The look is strictly monochrome with no color, square corners with no rounded edges, serif headings over a sans body, white paper cards carrying a soft shadow on a light gray canvas, an optional white sidebar for navigation, and bordered monochrome badges. Use this skill whenever the user asks for an HTML report, an HTML page, a writeup or summary as HTML, an analysis or feasibility or research document, a candidate comparison, a dashboard style page, or any self contained HTML deliverable, even when they do not name the style, so the output always matches the house look. Do not invent colors and do not round any corner.
---

# HTML Reports

This skill reproduces one fixed visual language for self contained HTML deliverables. Read it, then start from the bundled template at `assets/report-template.html` and pour the content into it rather than restyling from memory. The template already carries every token and component described here.

## The look in one breath

A light gray canvas holds a column of white paper cards that scroll continuously, never split into pages. An optional white sidebar on the left carries navigation. Everything is monochrome, corners are square, headings are serif over a sans body, and the paper surfaces float on a soft shadow. The result reads like a clean printed document rather than a web app.

## Non negotiables

These are the rules that make the style recognizable. Breaking any one of them breaks the look.

- **No color at all.** Work only in the grayscale token set below. No blues, greens, oranges, or accent hues anywhere, not in links, badges, callouts, list markers, or borders. Meaning comes from weight, borders, and headings, never from color.
- **No rounded corners anywhere.** Every card, badge, box, table, and input has square corners. Never set a border radius.
- **Two fonts only, serif headings over a sans body.** The whole document uses exactly two families, a serif for headings and a sans for everything else. Never introduce a third. See Typography below for the split and the heading scale.
- **Soft shadows on paper.** Cards and the sidebar sit on faint shadows built from black alpha, which is not color. This is the only depth cue.
- **Follow the writing rules below** in every word of visible text, since these documents are read closely.

## Typography

The type system is deliberately small. Two fonts, and headings that stop at three levels.

The two fonts and when to use each.

- **Serif, Georgia.** Used only for headings and for the single emphatic figure in a section, such as the estimate value. Serif marks a titled surface, so seeing it tells the reader this is a title or the one number that matters.
- **Sans, the system stack.** Used for everything else. All body copy, table cells, badges, list text, and the small uppercase labels are sans. If text is meant to be read rather than to title something, it is sans.

Headings stop at three levels, and every heading is serif.

- **h1** is the document title or the sidebar title. It is the smallest of the three by size because it is a running label rather than a page opener.
- **h2** is the single overview heading at the top of the first card, the largest type in the whole document, used once.
- **h3** is a section card title, one per section card.
- **There is no h4 or below.** Inside a section card the only heading is the card title itself, and every subsection under it is introduced by an `.eyebrow` label rather than a further heading. The small uppercase labels that head a subsection, such as the size line or the who it helps list, are that eyebrow, a bold uppercase sans line in the muted tone. Using a heading tag for them would break the scale, so they are always a styled label instead.

Body text is 15px at line height 1.6. The three headings sit at roughly 18px for h1, 27px for h2, and 23px for h3, all serif and bold.

## Layout

Two layouts are supported. Pick the sidebar layout when there are several sections a reader will jump between, and the single column when the piece is short or linear.

- **Sidebar and paper.** A fixed white sidebar about 320px wide on the left, a light gray main canvas on the right, and a centered column of white cards capped around 880px. The sidebar lists an overview link plus one link per section. Each sidebar row stacks a bold identifier on top and a muted name below, with any badge pinned to the right edge so it never overlaps wrapping text.
- **Single column paper.** Drop the sidebar and center the same card column on the gray canvas.

The first card is always an overview that frames the document, and each following section is its own card. Section cards lead with the serif title, then a small meta row directly beneath it holding any reference link and a size or status badge, and an optional as of date in the muted body size when the section reflects a source that can change under you, such as a ticket.

When the sidebar is present the template bundles a small scroll spy script, so keep it. As each section scrolls under a fixed line near the top of the viewport, its sidebar link gets the active class and the URL hash updates, so the reader always knows which section is on screen and can link straight to it. It is vanilla JS built on an IntersectionObserver with a scroll and resize listener, it needs no change as long as every sidebar link points at a section id, and the active row is marked by the same soft fill and left bar as hover with the identifier underlined. Drop the script only when you drop the sidebar.

## Design tokens

Use these exact values. They live in `:root` in the template.

```
--bg:    #eceded   /* gray canvas behind the cards */
--paper: #ffffff   /* cards and sidebar */
--ink:   #1a1a1a   /* primary text, borders that must read */
--muted: #666666   /* secondary text */
--faint: #8a8a8a   /* footnotes, least important text */
--line:  #d9d9d9   /* card and structural borders */
--hair:  #ececec   /* light dividers inside a card */
--soft:  #f5f5f5   /* filled callout backgrounds */
serif: Georgia, "Times New Roman", serif
sans:  -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif
```

Body text is 15px at line height 1.6. Card padding is roughly 34px by 40px. Card shadow is `0 1px 2px rgba(0,0,0,.05), 0 6px 22px rgba(0,0,0,.05)`. The sidebar shadow is `2px 0 10px rgba(0,0,0,.04)`.

## Components

- **Card.** White paper, a 1px `--line` border, the soft shadow, square corners, generous padding, stacked with about 26px between cards.
- **Badge.** A square chip with a 1px `--ink` border, dark text on white, small and bold. Never filled with color. Use a single letter in the sidebar and a full word inside a card.
- **Table.** Borderless outer frame, hairline row dividers in `--hair`, an uppercase muted header row, square everything.
- **Supported and limits lists.** Two columns under a card. Supported items are marked with a check and limit items with a cross, the matched ballot pair, both bold in `--ink`. The heading carries the meaning, the marker is only a cue, so keep them a consistent set rather than mixing a check with a dash or a square. Both markers are the same size and weight, and they align to the first line of their item so they never float above the text.
- **Value or highlight list.** Clean rows separated by a hairline divider, no boxes and no left bar, used for the punchy per role statements. Keep these plain so they read as a list rather than as a stack of callouts. State each role once. Do not pair a short who it helps list with a longer what it solves list, they cover the same roles and read as repetition, so give each audience a single row that names the role and the concrete payoff, and vary the phrasing so the rows do not chant the same opening.
- **Choices list.** A compact single column list with no dividers, each row a short bold fork the reader decides followed by what each way costs or simplifies. Use it when each fork needs only one short line. Keep it visually lighter than the value list so the two do not blur together.
- **Decision fork.** A two column grid, row aligned, the reader's choice on the left under a what you choose header and what it costs on the right under a what it takes header. Use it, rather than the choices list, when each fork needs an explicit cost answer set beside it, and only when the size or shape of the thing genuinely depends on the reader's answer. It is lighter than the supported and limits split, and it collapses to stacked pairs on a narrow screen. When no choice truly swings the work, leave it out.
- **Estimate line.** The label then value rhythm of every other block, with the uppercase sans label on its own line and no divider above it. Prefer the plain line, a sentence or two in the body size that reads as a consequence of the scope rather than a headline. Reserve the bold serif figure for a single emphatic number, such as a dollar amount or a count, and never use it for a range or an estimate that wants a caveat, because a figure that large reads as a title and oversells the certainty.
- **Callout box.** A `--soft` filled box with only a 3px `--ink` left bar and no surrounding border, used for the how to approach or key takeaway block. The fill alone sets it apart from the paper, so a full border would just compete with the bar. This is the one place a left bar is welcome, because it is a single deliberate accent rather than a repeated list style.
- **Note box.** A bordered white box in muted text for a caveat, with a bold lead in like a short label followed by the note.

## How to build

1. Copy `assets/report-template.html` to the destination the user wants.
2. Set the `<title>`, the sidebar heading, and the sidebar navigation rows.
3. Write the overview card, then one section card per topic, following the header pattern of serif title then meta row.
4. Keep all of it in one file. Inline every style, embed any image as a data URI, and never link an external stylesheet, font, or script, so the file opens cleanly from disk.
5. Reread the output against the non negotiables and the writing rules before handing it over.

## Writing rules

Every word of visible text follows these.

- Never use em dashes, en dashes, or hyphens in prose. Rephrase instead. Identifiers that legitimately contain a hyphen, such as a ticket key, are fine as names.
- Use only periods and commas for punctuation. No colons, semicolons, or other marks in sentences.
- Write plain, clear, cohesive sentences, and prefer flowing prose over heavy bullet formatting when prose reads well.
- Success is silent and errors are loud. If the document reports on work, state plainly what is done and what is not, without hedging.
