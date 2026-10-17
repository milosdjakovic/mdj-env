# Obsidian

Searches the notes in every vault Obsidian knows about and opens the chosen one in
Obsidian. Typing searches through the shared search every list uses, the note's name
first and its folder after, a word at a time in any order. A query always trails two
action rows, one that creates a note named by the typed words and one that hands them to
Obsidian's own full text search, and when nothing matches those two are the whole list.
With nothing typed, notes opened through this tool lead the list and the rest follow by
modification time. Once something is typed the best match leads, and a note opened here
only goes ahead of notes that match equally well. Notes under the vault's own excluded
files setting sort after every other match rather than disappearing.

Appears in the launcher under Tools as Search Obsidian, wearing the application's own
icon, and can be searched without leaving the launcher by typing ob or obsidian. It has
no key of its own, deliberately, since a typed word already reaches it. Every note row
carries the note emoji, and the create and search rows each carry their own face.

The in list keys are the shared navigation set alone, with Return opening the chosen
note.

It needs the Obsidian application itself, which owns the vault registry this plugin
reads and is where every chosen note opens, and without it the plugin is not wired at
all. Vaults come from that registry rather than from any list here, and notes come from
reading the vault directories directly, so the list is fresh on every open and works
while Obsidian is not running.
