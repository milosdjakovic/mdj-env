# Iris alias display

Status. Fixed on the fork branch `fix/alias-display-preserves-typed-command`, built into the
pinned binary, tracked against upstream by `src/check-iris-upstream.sh`.

## Now

Iris expands a shell alias so the target's spec can answer, which it has to do, and then never
puts the typed word back. With `cd` aliased to zoxide the rows read `z /path`, and ghost text
dies from the same cause, since it only draws when the top result has the literal buffer as a
prefix and `z ` never has `cd ` as one. One bug, two symptoms. Upstream issue 158. The fork
carries the fix as a single commit above upstream so it can be offered back unrewritten.

`src/check-iris-upstream.sh` answers on each run whether upstream still needs the patch, by
laying the branch's own tests onto an unmodified upstream checkout and running them there. A
branch whose tests pass on vanilla describes behaviour upstream now has and can go.

## Rejected

- **Configuring around it with `expand-alias`.** 2026-09-14, before 8f21edf. That option governs
  something else entirely, whether iris rewrites the literal prompt text on space. No
  configuration option touches the display bug.
- **Carrying the fix as a loose diff over the release binary.** 2026-09-14, before 8f21edf.
  A fork with one commit per patch on its own branch is what lets each patch be offered back
  and measured against upstream independently.

## Log

### 2026-09-14 14:02

8f21edf. Iris arrives, built from the fork rather than installed, because the released binary
has this defect and the appearance one and neither can be configured around. The build pins one
commit into `~/.local/bin`, so two machines build the same binary.

### 2026-09-14 14:35

4361b76. `src/check-iris-upstream.sh` added, because a fork stops asking whether upstream has
moved. It reads the changelog rather than the log, tests each patch against vanilla upstream,
and rebases each in a throwaway worktree so a conflict is known before anyone commits to it.
It reports and changes nothing. Which branch to watch was settled once, `main`, since `dev`
reads like where new work lands and is not.
