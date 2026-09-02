# Risk Medication Follow Up Plugin Showcase Video

Approved 2026-09-02. A follow up walkthrough for a client, recorded against seeded data where every claim below was verified on the running screen first.

## Opening

Hi everyone. This is a quick follow up walkthrough for the high risk medication follow up plugin. Since the previous showcase covered the basics, I will just show you what changed.

## Program management screen

Let's start on the program management screen, right here in the left menu.

### Tie Program To Medication Class

Before, a program only carried a name we typed in as free text, nothing actually connected it to the medications themselves. Now, when we create a program, we tie it to a medication group. And to find that group, I can search either way. I can type the name of the group, like statins, and it finds the Statins group. Or I can type a specific medication (`atorvastatin`), and it lands on the same group.

### Program Creation and Activation

The other change is how programs go live. Now, a new program starts out deactivated. The Activate button is grayed out, and hovering over it shows why, the program needs at least one step first. Once a step is added, the button turns green and the program can be activated.

### Program Deactivation

Hovering the deactivate button shows The tooltip which explains what will happen, the patients already on the program keep going and no more patients can be enrolled on this program.

## Patient chart

Now let's move over to a patient chart. This is Marta.

### See Patients Active Programs

The banner at the top-left shows this patient is already running on a program.

### Follow Ups Right Side Panel

Follow ups now lives in two places, at the chart level and on each note. It's the same view, the chart one lists every note with matching prescriptions, and the note one filters down to that note. Each note title is a link, and clicking it scrolls that note into view.

### Two Programs Matched On Single Prescription

Here, one medication matches two different programs, so we get two cards, and we can start either one, or both. In this case one of the matched programs is already started, and we can see that the second card shows a warning that the other program is already running on this medication, so starting it would put the patient on both.

### No Programs Exist For Matched Prescription

We can see that this prescription here has no program coverage, so we can't enroll the patient on it.

### Starting A Program

Now I'll start a couple of programs to show the difference. This first one, the prescription date doesn't overlap any of the defined steps, so it starts clean. And as you can see, the moment it starts, a new banner appears at the top-left.

### Starting A Program With Overdue Step

But this one down here was prescribed a while back, so some steps are already overdue. When I hit Start, I get this catch up dialog, and I can check off exactly which of the overdue steps we still want to run.

## Closing

That's it for the changes. Thanks for watching, and reach out if you have any questions.
