---
name: writing-patterns
description: Four cohesion patterns for ordering information across clauses so a reader can follow prose without effort. Use this skill whenever the user is drafting or revising prose another person will read, a Slack message or an email, a paper or an article, a software spec or a design document, a proposal, a README, a commit message, and whenever they ask why a paragraph reads badly, ask for something to be tightened, or hand over a draft for editing. The skill diagnoses a passage by reading only the first few words of every clause, then names which of the four patterns fits the writer's intent and rebuilds the passage on it. It governs the ordering of information rather than the voice, so it composes with any tone and with the user's own style rules.
---

# Writing Patterns

This skill is about one thing, the order in which information reaches a reader. It says nothing about word choice, tone, or register, and it never overrides the user's style rules. It answers a different question, which sentence element goes first and which goes last, and getting that wrong is what makes a grammatically perfect paragraph feel wrong.

## The principle underneath all four patterns

Every clause has two zones. The **topic** is the opening element, what the clause is about. The **comment** is everything after it, what is being said. Readers use those zones to decide what the passage as a whole is about, and they do it automatically, so the zones are not stylistic slots. They are load bearing.

The rule is that **old information goes in the topic and new information goes in the comment.** The topic is the doorstep the reader is already standing on. The comment is the room they walk into. Put new material in the topic and you have asked the reader to stand somewhere they have never been.

Two versions of the same content show it. First the broken one.

> Things that happen are not what produces happiness. Good fortune and random chance don't result in it either. Money can't buy it and power can't command it. Outside events do not determine it. Preparation, cultivation, and private defense by each person are what this condition requires.

Nothing there is ungrammatical and no fact is missing, yet it reads badly. Now the original, from Csikszentmihalyi.

> Happiness is not something that happens. It is not the result of good fortune or random chance. It is not something that money can buy or power command. It does not depend on outside events, but rather on how we interpret them. Happiness, in fact, is a condition that must be prepared for, cultivated, and defended privately by each person.

The difference is only the ordering. The broken version puts *things that happen*, *good fortune*, *money*, *outside events*, and *preparation* in the topic slots, which is five new elements and no subject. The original puts *happiness* in every one.

**This gives the diagnostic that drives the whole skill.** Strip a passage down to the first few words of each clause, read that list alone, and ask what the passage is about. If the list answers, the passage is coherent. If it does not, no amount of rewording at the sentence level will fix it, because the defect is in the ordering.

## Pattern 1, constant topic

**Shape.** The same element occupies every topic slot, through plain repetition, a pronoun, or a synonym. All the new material accumulates in the comments.

**What it does.** It pins the reader to one element and lets many ideas attach to it. The reader stands on the doorstep and looks in every direction from there. The Csikszentmihalyi passage above is this pattern.

**Use it for** defining a term, characterizing one thing, unpacking a multifaceted idea, stating what something is and is not, and any passage where the reader must not lose the subject under the detail.

**The cost.** It is static. Nothing moves, so a long stretch of it feels stagnant. Reserve it for the passage that genuinely needs one thing unpacked, and get out of it once the thing is unpacked.

## Pattern 2, linking

**Shape.** Each topic picks up the element that ended the previous comment. New, then old, then new again, stepwise.

**What it does.** It carries the reader forward. Each clause hands them a new vantage point rather than returning them to the doorstep. From Gleick.

> Outside his window, Lorenz could watch real weather, the early morning fog creeping along the MIT campus or the low clouds slipping over the roofs from the Atlantic. Fog and clouds never arose in the model running on his computer. The machine, a Royal McBee, was a thicket of wiring and vacuum tubes that occupied an ungainly portion of Lorenz's office.

*Fog and clouds* end the first sentence and open the second. *His computer* ends the second and opens the third as *the machine*. The passage closes back in Lorenz's office, where it began.

**Use it for** process, method, sequence, a causal chain, a failure trace, movement through space, and the narrative of what happened. It is the natural pattern for a bug writeup and for a commit message that explains how a defect arose.

**The cost, and it is the real one.** Every link can be locally valid while the passage as a whole drifts to somewhere nobody wanted to go. Watch it happen.

> Soon, Portland will be the coffee roasting hub of the nation. The aroma of roasting beans fills the streets, and gleaming espresso machines line the counters. The machines remind me of my dad's old typewriter, covered with keys I would press randomly. His typewriter always jammed on me. That's why I avoided it. I prefer to write with blue pen on yellow legal pads.

The chain is perfect and the passage is about nothing. **Guard against it two ways.** Read the topic list and ask whether those elements could stand on one stage together, and where it fits, close the loop by ending near where the passage opened.

## Pattern 3, the umbrella

**Shape.** The topics all differ and never repeat, and coherence comes instead from a preceding clause whose comment names the whole that every one of them belongs to.

**Why it works.** Walk into a cathedral and you are not surprised to meet the nave, the crypt, and the pulpit. Once the whole is on stage, its parts need no introduction. From Pinker.

> When neuroscientists look directly at the brain, they can actually see language in action in **the left hemisphere**. The anatomy of the normal brain, its bulges and creases, is slightly asymmetrical. In some of the regions associated with language, the differences are large enough to be seen with the naked eye. Aphasics' brains almost always show lesions in the left hemisphere.

*The anatomy*, *the regions*, and *aphasics' brains* are three unrelated topics that read as one passage, because the first comment put the whole they belong to on stage.

**Use it for** a taxonomy, a categorization, the anatomy of a system, a component breakdown, and any decomposition of one thing into parts that do not share a name.

**The failure mode is leaving the umbrella implied.** If the category lives only in the writer's head, every clause after it reads disjointed. This passage has the defect.

> After gathering the smallest and most colorful leaves from the maples and oaks in our backyard, we place the leaves between sheets of blotter paper, which we then cover with a large heavy book. In just a day or two, the leaves are ready to be mounted on cards. We use plain index cards folded in half.

One sentence in front of it and the whole thing snaps into place. "Each Thanksgiving we make place cards decorated with pressed autumn leaves." **This is the single highest yield edit in the skill.** When a draft reads scattered, the fix is usually not rewording anything, it is writing the missing naming sentence.

## Pattern 4, theme preview

**Shape.** An index clause names the strands in its comment, A, B, and C. Then one unit per strand, in the same order, each opening on the strand it develops.

From Haidt.

> Shweder et al. found three major clusters of moral themes, which they called the ethics of **autonomy**, **community**, and **divinity**. The ethic of **autonomy** is based on the idea that people are first and foremost autonomous individuals. The ethic of **community** is based on the idea that people are first and foremost members of larger entities. The ethic of **divinity** is based on the idea that people are first and foremost temporary vessels within which a divine soul has been implanted.

**Use it for** enumerated content of any kind, three requirements in a spec, three reasons in an argument, the options in a decision, the sections of a document.

**The failure mode is synonym drift.** Announce *community* and then develop it as *groups* and the reader has to carry a private mapping while reading. Repeat the announced term exactly. Morphological variants are fine, *autonomy* and *autonomous*, *community* and *communal*, because they still point at the announced word. Reach for a synonym and the structure comes apart. **Order counts too.** Announce A, B, C and develop them in that order.

## Choosing among them

| The reader needs | Pattern | Opening move |
|---|---|---|
| To hold one thing steady while detail accumulates | Constant topic | Name the thing and keep it in every topic slot |
| To follow how one state became another | Linking | End each sentence on what the next one opens with |
| To see the parts of something | Umbrella | Name the whole first, in a comment |
| To track a fixed number of strands | Theme preview | Announce them, then develop in order with the same words |

When a passage resists all four, the usual cause is that it is doing two jobs at once. Split it and give each half its own pattern.

## Levels of resolution, and nesting

These patterns are scale free. They run inside a paragraph, across the paragraphs of a section, and across the sections of a document, and they nest inside each other.

The common composition is **theme preview at the top, something else inside each strand.** A document announces three concerns, then gives each concern its own section, and inside a section the passage that defines a term runs on constant topic while the passage that traces a sequence runs on linking. A component breakdown opens with an umbrella sentence and then runs linking inside each component's description.

At document scale the theme preview is simply an honest outline, and the signposts that keep the reader placed are the plain ordinals, first, second, third.

## Applying it to the three real cases

**Messages, Slack, and email.** Lead with the ask, then the reasoning, per the user's standing preference. When the message asks for more than one thing, that is a theme preview and it becomes a short numbered block, announced by count. "Three things I need from you." When the message reports status on one thing, it is constant topic, so keep that one thing in every topic slot rather than opening successive sentences on the ticket, the branch, the reviewer, and the deploy. Never open a message on the linking pattern, since drift in a message reads as burying the point.

**Papers and long form.** Theme preview carries the structure, at section scale and again at paragraph scale. Constant topic carries the passage that establishes the central construct, because that is the one the reader must not lose. Linking carries the method and any causal argument. Every decomposition gets its umbrella sentence in front, and in academic writing that sentence is what a reader skimming headings and openers is actually reading.

**Software specs and design documents.** These are mostly umbrella and theme preview, and the two most common defects are both ordering defects. A component list with no sentence naming the system reads as an unrelated pile, which is the missing umbrella. A requirements list that announces three requirements and then names them differently in the body forces the reader to maintain a mapping, which is synonym drift, and in a spec it also invites two people to believe the requirement means two different things. Use linking for the flow, the failure path, and the sequence of operations, and use constant topic for the passage that states one component's contract or one invariant, since that is exactly a definition.

**Commit messages that explain a defect** are linking, end to end, because they are causal narratives. Take the drift guard seriously in a long one, and close the loop by ending on the behaviour the opening described.

## The revision procedure

When editing anything, own draft or the user's, run this before touching a single word.

1. **Extract the topic list.** Take the first few words of every clause in order and put them in a list on their own.
2. **Read the list alone and ask what the passage is about.** If it does not answer, stop. The defect is structural and rewording will not reach it.
3. **Identify the pattern the topics actually form,** one repeated element, a chain, a scatter, or an announced set.
4. **Compare it to the job the passage is doing.** A definition running on linking, or a process running on constant topic, is a mismatched pattern and gets rebuilt rather than polished.
5. **For a scatter, look for the umbrella sentence.** If there is none, write it. This resolves most scattered drafts on its own.
6. **For an announced set, check the terms are verbatim and the order holds.**
7. **Then sweep for new material sitting in topic slots.** Each one moves to the end of the previous sentence, which is where the reader was ready to meet it.

Only after that is finished does the wording matter.

## Keep this skill alive

- When the user corrects an ordering decision, or names a pattern that worked in a real draft, fold it back into this file in the same session.
- When a passage is approved and its structure is worth reusing, save it under `assets/`, named by date and subject, with a one line note on which pattern it runs.
- This skill lives in the mdj-env repository and is stowed into the home directory, so edit it at `dotfiles/claude/.claude/skills/writing-patterns/` and remind the user to commit mdj-env when it changes.
