#!/bin/bash
set -e

# Ask, for every carried fork, the question a fork stops asking about itself.
#
# What has upstream released since the pin. Is each carried patch still needed. Does it still
# rebase cleanly. And have any of the upstream links a decision here rests on moved.
#
# It reports and changes nothing. It never moves a pin, never pushes, never edits a branch and
# never builds the installed binary, which is the same split check-dependencies.sh keeps,
# because every answer it gives leads to a decision a person has to make.
#
# It knows git, gh and a declaration format. It does not know which forks exist, nor what
# language any of them is written in. Whether a patch is still needed is delegated to a prove
# executable at each fork's own root, found by name. forks/CLAUDE.md carries the contract.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE="$HOME/.cache/mdj-env"

ONLY="${1:-}"
warnings=0
errors=0

decl_first() {
    awk -F'|' -v key="$2" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { k = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k) }
        k == key { v = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit }
    ' "$1"
}

decl_rows() {
    awk -F'|' -v key="$2" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { k = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k) }
        k == key {
            line = ""
            for (i = 2; i <= NF; i++) {
                f = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
                line = (line == "" ? f : line "|" f)
            }
            print line
        }
    ' "$1"
}

shopt -s nullglob
declarations=("$REPO_ROOT"/forks/*/FORK)
if (( ${#declarations[@]} == 0 )); then
    echo "==> Checking carried forks..."
    echo "  no fork is declared under forks/"
    exit 0
fi

for declaration in "${declarations[@]}"; do
    dir="$(dirname "$declaration")"
    name="$(decl_first "$declaration" name)"
    [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue

    upstream_url="$(decl_first "$declaration" upstream)"
    fork_url="$(decl_first "$declaration" fork)"
    base="$(decl_first "$declaration" base)"
    pin="$(decl_first "$declaration" pin)"
    decisions="$(decl_first "$declaration" decisions)"

    echo
    echo "==> $name, pinned at ${pin:0:7} on $base"
    [[ -n "$decisions" ]] && echo "  the record is $decisions"

    worktree="$CACHE/$name-build"
    if [[ ! -d "$worktree/.git" ]]; then
        echo "  WARN  no checkout at ~/.cache/mdj-env/$name-build, src/build-forks.sh owns it and has not run" >&2
        warnings=$((warnings + 1))
        continue
    fi

    git -C "$worktree" remote get-url upstream >/dev/null 2>&1 || \
        git -C "$worktree" remote add upstream "$upstream_url"
    git -C "$worktree" remote set-url upstream "$upstream_url"
    git -C "$worktree" remote set-url origin "$fork_url"
    git -C "$worktree" fetch --quiet --prune origin 2>/dev/null || true
    if ! git -C "$worktree" fetch --quiet --prune --tags upstream 2>/dev/null; then
        echo "  WARN  upstream cannot be reached, so nothing below is current" >&2
        warnings=$((warnings + 1))
        continue
    fi

    # What upstream has done since the pin. Tags rather than commits, because a tag is what a
    # person decides about and a commit count is noise.
    # Release tags only. Upstream also tags every preview build, and a preview is not a thing
    # anyone here decides about, so counting them would report movement on almost every run and
    # the report would stop being read.
    glob="$(decl_first "$declaration" releases)"; [[ -n "$glob" ]] || glob='v[0-9]*'
    exclude="$(decl_first "$declaration" releases-exclude)"
    if [[ -n "$exclude" ]]; then
        newer="$(git -C "$worktree" tag --sort=-creatordate --list "$glob" --ignore-case 2>/dev/null | grep -v -- "${exclude//\*/}" | awk -v base="$base" '$0 == base { exit } { print }')"
    else
        newer="$(git -C "$worktree" tag --sort=-creatordate --list "$glob" 2>/dev/null | awk -v base="$base" '$0 == base { exit } { print }')"
    fi
    if [[ -z "$newer" ]]; then
        echo "  upstream has released nothing since $base"
    else
        count="$(printf '%s\n' "$newer" | grep -c .)"
        echo "  upstream has released $count since $base, newest first"
        printf '%s\n' "$newer" | head -6 | sed 's/^/    /'
    fi

    # Whether each patch is still needed, and whether it still rebases. The first question can
    # only change when upstream has released something, and answering it costs a full build of
    # vanilla, so it is asked then and not on every run.
    while IFS='|' read -r branch what link; do
        [[ -z "$branch" ]] && continue
        echo "  patch $branch"
        [[ -n "$what" ]] && echo "    $what"
        [[ -n "$link" ]] && echo "    $link"

        if ! git -C "$worktree" rev-parse --verify --quiet "origin/$branch" >/dev/null; then
            echo "    ERROR the fork has no branch by that name" >&2
            errors=$((errors + 1))
            continue
        fi

        prove="$dir/prove"
        if [[ -z "$newer" ]]; then
            echo "    still needed, upstream has released nothing that could have changed it"
        elif [[ ! -x "$prove" ]]; then
            echo "    WARN  cannot say whether upstream has taken it, the fork ships no prove script" >&2
            warnings=$((warnings + 1))
        else
            probe="$CACHE/$name-probe"
            rm -rf "$probe"
            newest="$(printf '%s\n' "$newer" | head -1)"
            git -C "$worktree" worktree prune >/dev/null 2>&1 || true
            if git -C "$worktree" worktree add --quiet --detach "$probe" "$newest" 2>/dev/null; then
                set +e
                "$prove" "$probe" "$branch" "$worktree"
                answer=$?
                set -e
                case "$answer" in
                    0) echo "    UPSTREAM HAS IT at $newest, this patch can go, read forks/CLAUDE.md for what that means" ;;
                    1) echo "    still needed, unmodified $newest does not do it" ;;
                    *) echo "    WARN  this machine cannot answer right now" >&2; warnings=$((warnings + 1)) ;;
                esac
                git -C "$worktree" worktree remove --force "$probe" >/dev/null 2>&1 || rm -rf "$probe"
            else
                echo "    WARN  could not lay out a vanilla checkout at $newest" >&2
                warnings=$((warnings + 1))
            fi
        fi

        # Rebase in a throwaway worktree, so a conflict is known before anyone commits to
        # resolving it, and nothing here touches the branch itself.
        if [[ -n "$newer" ]]; then
            newest="$(printf '%s\n' "$newer" | head -1)"
            rebase="$CACHE/$name-rebase"
            rm -rf "$rebase"
            git -C "$worktree" worktree prune >/dev/null 2>&1 || true
            if git -C "$worktree" worktree add --quiet --detach "$rebase" "origin/$branch" 2>/dev/null; then
                if git -C "$rebase" rebase --quiet "$newest" >/dev/null 2>&1; then
                    echo "    rebases cleanly onto $newest"
                else
                    git -C "$rebase" rebase --abort >/dev/null 2>&1 || true
                    echo "    WARN  does not rebase cleanly onto $newest, expect conflicts" >&2
                    warnings=$((warnings + 1))
                fi
                git -C "$worktree" worktree remove --force "$rebase" >/dev/null 2>&1 || rm -rf "$rebase"
            fi
        fi
    done < <(decl_rows "$declaration" patch)

    # The upstream links a decision here rests on. A fix, a reopened issue or an answered
    # discussion reaches this repository through this rather than by being noticed by accident.
    if ! command -v gh >/dev/null 2>&1; then
        echo "  WARN  gh is not on PATH, so the watched links were not read" >&2
        warnings=$((warnings + 1))
    else
        while IFS='|' read -r url was what; do
            [[ -z "$url" ]] && continue
            now="$(gh api "$(printf '%s' "$url" | sed -E 's#https://github.com/([^/]+)/([^/]+)/issues/([0-9]+)#repos/\1/\2/issues/\3#; s#https://github.com/([^/]+)/([^/]+)/pull/([0-9]+)#repos/\1/\2/pulls/\3#')" --jq .state 2>/dev/null || true)"
            case "$url" in
                *"/discussions/"*)
                    # A discussion has no state, so what matters is whether anyone has answered.
                    number="${url##*/}"
                    repo="$(printf '%s' "$url" | sed -E 's#https://github.com/([^/]+/[^/]+)/discussions/.*#\1#')"
                    now="$(gh api "graphql" -f query="query{repository(owner:\"${repo%%/*}\",name:\"${repo##*/}\"){discussion(number:$number){comments{totalCount}}}}" --jq '.data.repository.discussion.comments.totalCount' 2>/dev/null || true)"
                    if [[ -z "$now" ]]; then
                        echo "  WARN  could not read $url" >&2
                        warnings=$((warnings + 1))
                    else
                        echo "  $url, $now comments, last seen $was"
                    fi
                    continue
                    ;;
            esac
            if [[ -z "$now" || "$now" == *"Not Found"* || "$now" == *"{"* ]]; then
                echo "  WARN  could not read $url" >&2
                warnings=$((warnings + 1))
            elif [[ "$now" != "$was" ]]; then
                echo "  MOVED $url is $now, the declaration says $was"
                echo "        $what"
            else
                echo "  $url is still $now"
            fi
        done < <(decl_rows "$declaration" watch)
    fi
done

echo
if (( errors > 0 )); then
    echo "Fork check found $errors error(s) and $warnings warning(s)."
    exit 1
fi
echo "Fork check passed, $warnings warning(s)."
