---
name: showcase-walkthrough
description: Write the cue sheet for a showcase or walkthrough video in Milos's voice. Use this skill whenever the user asks for a video scenario, a walkthrough script, a demo script, showcase sentences, or anything they will read aloud while recording a product demonstration, whatever the product is. The output is a markdown cue sheet of short spoken lines the user reads verbatim on camera, casual American English, flat demonstration with zero selling language and zero anthropomorphism, every on screen claim verified against the running software first. Also use it when the user corrects the wording of an existing script, and fold that correction back into this skill in the same session.
---

# Showcase Walkthrough Scripts

This skill produces one thing, a cue sheet the user reads aloud while recording a walkthrough video. The sentences are the deliverable. Structure comes cheap, the voice is the hard part, and this file carries the voice as learned from real corrections, so read the whole thing before writing a single line.

The audience is usually a client or stakeholder. The goal is to show the work in its best light through clear demonstration, a story that moves from the business need to the feature to how it works on screen. Best light never means sales language. It means the viewer understands what they are looking at and why it matters, without ever feeling pitched to.

## Ask first, three questions at most

Before writing, settle these. Ask only the ones the conversation has not already answered, and keep it to a sentence each.

1. **Is this a first showcase or a follow up?** A first showcase tells the story from the business need. A follow up opens by saying the basics were covered last time and shows only what changed.
2. **What did the audience last see?** This is the one thing that can never be inferred. Repository history, specs, and commit logs say what the code did, not what the audience was shown. In one real case the code had carried a feature for weeks, but the audience had seen an earlier build without it, so calling it old would have been wrong on camera. When in doubt, ask the user what the previous video showed.
3. **What data is prepared?** A script that says two cards appear must be written against an environment where two cards actually appear. Ask what is seeded, or check it, before promising it in a sentence.

## Ground every claim

Every sentence that describes the screen gets verified against the running software before it goes in the script. Read the actual button labels, the actual tooltip text, the actual warning wording, and script around what is really there. Paraphrase on screen text rather than quoting it, but never script a behaviour that was not checked. A cue line that promises something the screen does not do is worse than no line.

## The voice

Casual American English, first person, contractions welcome, respectful without being business formal. The user is showing their work to get feedback, not closing a deal. These rules come from real corrections and each one is firm.

| Never write | Because | Write instead |
|---|---|---|
| pretty handy, that's cool, nice case | Selling language. This is a demonstration, not a pitch. | State the fact and stop. |
| the search just got smarter | Marketing framing of a change. | Say what changed. "What changed is the search. I can now type the name of the group." |
| the plugin is honest about it | Anthropomorphism. Software has no character traits. | "This prescription has no program coverage, and the card says so." |
| and it even shows me which products matched | Piling a bonus clause onto a point already made. | Cut it, or give it its own flat sentence only if it matters. |
| This is Marta. | Narrating what is visible on screen. | Cut it. The viewer can see. |
| This one is fresh, so I can start it | Telling the presenter what they already know about their own data. | Let the presenter point, script only what needs saying. |
| Either way works. So you can think in drugs or think in classes. | Summarizing a demonstration the viewer just watched. | Cut the recap, the demonstration carried it. |

More voice rules with no table row yet.

- Transitions are simple and spoken. "Let's start on the program management screen." "Now let's move over to a patient chart."
- Prefer "I will show you what changed" over "I want to showcase the changes." Say the plain verb.
- When a control explains itself on screen, script the pointing, not the content. "Hovering the Deactivate button shows a tooltip which explains what will happen" and then paraphrase it in one clause.
- A follow up opens close to this. "Hi everyone. This is a quick follow up walkthrough for the X. Since the previous showcase covered the basics, I will just show you what changed."
- A closing is two sentences. "That's it for the changes. Thanks for watching, and reach out if you have any questions."

## The shape of the cue sheet

Markdown, built to be glanced at mid recording.

- One H1 naming the video.
- H2 per screen or location, in the order the recording visits them.
- H3 per feature or moment under it.
- Short paragraphs of one to three spoken sentences each. No bullets inside the spoken lines, bullets read badly aloud.
- The story inside each screen runs need first, then the feature, then the interaction. Before and after framing works well for changes. "Before, a program only carried a name we typed in as free text. Now, when we create a program, we tie it to a medication group."
- Order the chart or product moments so each demonstration sets up the next, and say so in the script when one does. "I'll start a couple of programs to show the difference."

## Keep this skill alive

This is a living document and it only works if it stays current.

- When the user corrects a script's wording, fold the correction into the voice table above in the same session, with the wrong phrase, the reason, and the replacement.
- When a script is approved, save it whole under `assets/` in this skill as the newest exemplar, named by date and subject. Start every new script by reading the newest exemplar, one approved script teaches the voice better than every rule here.
- This skill lives in the mdj-env repository and is stowed into the home directory, so edit it at `dotfiles/claude/.claude/skills/showcase-walkthrough/` and remind the user to commit mdj-env when it changes.

## Exemplar

The newest approved script is in `assets/`, currently `assets/2026-09-02-medication-followup.md`. Read it before writing.
