#!/bin/bash
set -e

# Report what upstream iris has done since this repository's fork branched, and say for each
# patch the fork carries whether it is still needed.
#
# This only reports. It never moves the pin, never pushes, and never edits a branch, which is
# the same split src/check-dependencies.sh keeps, because every answer it produces leads to a
# decision a person has to make. Reading what a release changed is judgment, and so is deciding
# that a conflict is worth resolving rather than dropping a patch.
#
# The question it exists to answer is the one that is easy to stop asking. A fork that carries
# a fix forever is a fork nobody notices upstream has already fixed, and it then sits between
# this machine and every feature released after it. So the useful test is not whether the patch
# still applies, it is whether vanilla upstream still needs it. That is asked by laying the
# branch's own tests onto an unmodified upstream checkout and running them there. A branch whose
# tests pass on vanilla is describing behaviour upstream now has, and the branch can go.
#
# The list below is the only thing that has to be written by hand. Which test files prove a
# patch, and which packages they live in, are both read out of the branch itself, so a third
# patch is one line here and nothing else.
#
# name | what it is
IRIS_PATCHES=(
    "fix/alias-display-preserves-typed-command|upstream issue 158, a suggestion reads back the alias target instead of the typed word"
    "feat/appearance-aware-theme|a theme carrying a half per terminal appearance, which upstream has no notion of"
)

UPSTREAM_REPO="https://github.com/versenilvis/IRIS.git"
UPSTREAM_BRANCH="upstream/main"
# Main is the only line worth watching. Upstream also has a dev branch, which reads like the
# place new work lands and is not, it forked in May 2026 and has four commits nobody merged,
# while every release since has been cut from main through pull requests. Checking it was a
# reasonable guess and the dates answered it, so this records the answer rather than leaving
# the guess there to be made again.

WORKTREE="$HOME/.cache/mdj-env/iris-build"
PROBE="$HOME/.cache/mdj-env/iris-probe"

if [[ ! -d "$WORKTREE/.git" ]]; then
    echo "==> Checking iris upstream..."
    echo "  no fork checkout at $WORKTREE." >&2
    echo "  src/build-iris.sh owns that clone, so run it once and this can read from it." >&2
    exit 1
fi

if ! command -v go >/dev/null 2>&1; then
    echo "  go is not on PATH, so the patches cannot be probed against vanilla upstream." >&2
    exit 1
fi

echo "==> Checking iris upstream..."

if ! git -C "$WORKTREE" remote get-url upstream >/dev/null 2>&1; then
    git -C "$WORKTREE" remote add upstream "$UPSTREAM_REPO"
fi
git -C "$WORKTREE" remote set-url upstream "$UPSTREAM_REPO"
git -C "$WORKTREE" fetch --quiet --prune origin
git -C "$WORKTREE" fetch --quiet --prune --tags upstream

# The fork's branches all sit on one upstream commit, so that commit is what "how far behind"
# is measured from. Asking git for it rather than naming it keeps this true after an update.
BASE="$(git -C "$WORKTREE" merge-base "$UPSTREAM_BRANCH" origin/main)"

show() { git -C "$WORKTREE" log --format='%h %s' -1 "$1"; }

echo ""
echo "==> Where the fork stands"
printf '  %-16s %s\n' "fork base" "$(show "$BASE")"
printf '  %-16s %s\n' "fork main" "$(show origin/main)"

behind="$(git -C "$WORKTREE" rev-list --count "$BASE..$UPSTREAM_BRANCH")"
if [[ "$behind" -eq 0 ]]; then
    printf '  %-16s %s\n' "upstream main" "no new commits since the fork base"
else
    printf '  %-16s %s\n' "upstream main" "$behind commit(s) the fork does not have"
    git -C "$WORKTREE" log --format='    %h %s' "$BASE..$UPSTREAM_BRANCH"
fi

# Nightly tags sit between the releases, so they are excluded, otherwise every answer here
# is the nightly of whatever commit is newest and no two of them mean anything to compare.
release() {
    git -C "$WORKTREE" describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*nightly*' \
        "$1" 2>/dev/null || echo "none"
}
printf '  %-16s %s\n' "release" "built from $(release "$BASE"), upstream is on $(release "$UPSTREAM_BRANCH")"

# What a commit means is readable rather than guessable, because upstream keeps a real
# changelog, one line per thing that changed where the log is one line per merge.
if [[ "$behind" -gt 0 ]]; then
    echo ""
    echo "==> What those commits say they changed"
    changes="$(git -C "$WORKTREE" diff "$BASE" "$UPSTREAM_BRANCH" -- CHANGELOG.md \
        | sed -n 's/^+\([^+].*\)/  \1/p')"
    if [[ -n "$changes" ]]; then
        echo "$changes"
    else
        echo "  nothing was added to the changelog, so read the commits above instead"
    fi
fi

# A detached linked worktree, so the probe cannot disturb the checkout src/build-iris.sh
# compiles from, and so an interrupted run leaves nothing behind that a later one trips over.
cleanup() {
    git -C "$WORKTREE" worktree remove --force "$PROBE" >/dev/null 2>&1 || true
    git -C "$WORKTREE" worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
git -C "$WORKTREE" worktree add --quiet --detach "$PROBE" "$UPSTREAM_BRANCH"

echo ""
echo "==> Whether vanilla upstream still needs each patch"

needed=0
droppable=0

for entry in "${IRIS_PATCHES[@]}"; do
    branch="${entry%%|*}"
    note="${entry#*|}"
    ref="origin/$branch"

    echo ""
    echo "  $branch"
    echo "    $note"

    if ! git -C "$WORKTREE" rev-parse --verify --quiet "$ref" >/dev/null; then
        echo "    no such branch on the fork, so nothing to probe"
        continue
    fi

    patch_base="$(git -C "$WORKTREE" merge-base "$UPSTREAM_BRANCH" "$ref")"

    # The branch's own tests are what state the behaviour it wants, so they are the probe.
    # Read them out of the branch rather than listing them here, so this keeps working when
    # a patch grows a test.
    test_files=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && test_files+=("$f")
    done < <(git -C "$WORKTREE" diff --name-only --diff-filter=ACMR \
        "$patch_base" "$ref" -- '*_test.go')

    if [[ "${#test_files[@]}" -eq 0 ]]; then
        echo "    the branch carries no tests, so there is nothing to prove it with"
        needed=$((needed + 1))
        continue
    fi

    # Lay only the tests onto unmodified upstream. The branch's own source stays out, so what
    # runs is upstream's behaviour measured against the branch's expectations.
    names=()
    pkgs=()
    for f in "${test_files[@]}"; do
        mkdir -p "$PROBE/$(dirname "$f")"
        git -C "$WORKTREE" show "$ref:$f" > "$PROBE/$f"
        while IFS= read -r name; do
            [[ -n "$name" ]] && names+=("$name")
        done < <(sed -n 's/^func \(Test[A-Za-z0-9_]*\)(.*/\1/p' "$PROBE/$f")
        pkgs+=("./$(dirname "$f")")
    done

    unique_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && unique_pkgs+=("$pkg")
    done < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    pkgs=("${unique_pkgs[@]}")
    run_pattern="^($(printf '%s|' "${names[@]}" | sed 's/|$//'))\$"

    out="$(mktemp)"
    if ( cd "$PROBE" && go test -count=1 -run "$run_pattern" "${pkgs[@]}" ) >"$out" 2>&1; then
        echo "    vanilla upstream PASSES the branch's tests, so upstream has this now"
        echo "    and the branch can be dropped, along with its merge on the fork's main"
        droppable=$((droppable + 1))
    elif grep -qE '\[build failed\]|undefined:|cannot use' "$out"; then
        echo "    the branch's tests do not compile against vanilla upstream, so nothing"
        echo "    of it exists there yet and the patch is still needed"
        needed=$((needed + 1))
    else
        echo "    vanilla upstream FAILS the branch's tests, so the patch is still needed"
        grep -E '^\s+.*_test\.go:[0-9]+:' "$out" | head -4 | sed 's/^/      /'
        needed=$((needed + 1))
    fi
    rm -f "$out"

    git -C "$PROBE" checkout --quiet -- .
    git -C "$PROBE" clean -fdq

    # Whether it still applies is a separate question from whether it is still wanted, and it
    # is only worth asking about a patch that is still wanted. Rebase rather than merge, since
    # each branch stays one series above upstream so it can be offered back unrewritten.
    if [[ "$behind" -gt 0 ]]; then
        git -C "$PROBE" checkout --quiet --detach "$ref"
        if git -C "$PROBE" rebase --quiet --onto "$UPSTREAM_BRANCH" "$patch_base" >/dev/null 2>&1; then
            ahead="$(git -C "$PROBE" rev-list --count "$UPSTREAM_BRANCH..HEAD")"
            echo "    rebases onto upstream main cleanly, $ahead commit(s)"
        else
            git -C "$PROBE" rebase --abort >/dev/null 2>&1 || true
            echo "    does NOT rebase onto upstream main cleanly, it needs resolving by hand"
        fi
        git -C "$PROBE" checkout --quiet --detach "$UPSTREAM_BRANCH"
        git -C "$PROBE" clean -fdq
    fi
done

echo ""
echo "==> What to do with that"
if [[ "$behind" -eq 0 ]]; then
    echo "  Upstream main has not moved, so there is nothing to take yet."
else
    echo "  Upstream main has moved. Rebase each patch that is still needed onto it, merge"
    echo "  them into the fork's main, move IRIS_COMMIT in src/build-iris.sh to that merge,"
    echo "  and run src/build-iris.sh."
fi
if [[ "$droppable" -gt 0 ]]; then
    echo "  $droppable patch(es) above are upstream now. Dropping one means deleting the"
    echo "  branch and reverting its merge from the fork's main, not only leaving it unbuilt."
fi
if [[ "$needed" -eq 0 && "$droppable" -gt 0 ]]; then
    echo "  With no patch left, the fork stops being needed and iris goes back to being an"
    echo "  ordinary package, which retires this script, build-iris.sh and the go dependency."
fi
