# QueryScope

Turns the first word typed into the launcher into a scope, so an alias followed by a space
hands the whole list over to one tool, for instance a v then a space for VPN or a k then a
space for keep awake, and deleting the space hands the list back. It has no key of its own and
no chooser, since it is reached only by typing inside a list that is already open.

A scope answers with rows and with what choosing one does, and it may answer with more than
that too, a peek that shows extra detail on a row without choosing it, a redirect that puts a
different word in the field instead of opening anything, and an action that flips something in
place and leaves the list open. The alias directory, listing every word that reaches a scope
this way, is itself one of these scopes.
