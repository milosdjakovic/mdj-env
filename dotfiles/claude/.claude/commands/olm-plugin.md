---
argument-hint: [plugin name or what it should do]
description: Build or modify an Olm Hammerspoon plugin through the olm-plugin skill
---

# Olm plugin work

`$ARGUMENTS` names the plugin or describes what it should do. If it is empty, ask what the
plugin is before reading anything.

This work happens in the mdj-env repository, which carries the rules as a project skill.
Invoke the `olm-plugin` skill with the Skill tool and follow it. If the skill is not listed,
you are not inside that repository and this command does not apply, so say so and point at
the mdj-env checkout, where the skill lives at `.claude/skills/olm-plugin/SKILL.md`. The
skill is the single source for this workflow, so do not duplicate its rules here or work
from memory of them.
