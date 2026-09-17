#!/bin/bash

# Set default application for common development file extensions
# Usage: ./set-dev-defaults.sh "App Name"
# Example: ./set-dev-defaults.sh "Zed"
#          ./set-dev-defaults.sh "Visual Studio Code"

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 \"App Name\""
    echo "Example: $0 \"Zed\""
    exit 1
fi

APP_NAME="$1"

# duti is declared in src/DEPENDENCIES, mapped in DEPENDENCIES.map and carried by the
# Brewfile, so putting it on the machine is the setup layer's job rather than this script's.
# This used to probe for it and then run an install command itself, which is the one thing the
# root CLAUDE.md forbids outright, because it duplicates an answer already held in three other
# places and all four then drift apart with nothing watching. Saying it is missing and where
# the answer lives costs two lines and cannot drift.
if ! command -v duti > /dev/null 2>&1; then
    echo "Error: duti is not installed."
    echo "       src/check-dependencies.sh names it and says where it comes from."
    exit 1
fi

# Get bundle identifier for the app
BUNDLE_ID=$(osascript -e "id of app \"$APP_NAME\"" 2>/dev/null)

if [ -z "$BUNDLE_ID" ]; then
    echo "Error: Could not find app \"$APP_NAME\""
    echo "Make sure the app is installed and the name is correct."
    exit 1
fi

# The handler of one extension as Launch Services will actually use it, as a bundle id, or
# nothing when duti cannot say. Read before and after every binding, because duti's exit code
# is not the answer. On macOS 27 a change of default handler is something the person is asked
# about, a dialog naming the old application and the new one, and `duti -s` returns zero the
# moment it has asked, before anybody has answered. That was measured by pointing .md and .log
# at TextEdit, which returned success, changed nothing, and put two dialogs on the screen. So
# the only report this script can stand behind is what the handler is once the call has
# returned, and an extension still on its old handler then is one with a dialog waiting, not
# a failure. One caveat. duti answers this from what Launch Services would open the file with,
# which is wider than which handler is bound to the type, so it says Zed for .rs on this
# machine, an extension the binding cannot attach to at all. That is why the untyped case is
# still read off the binding's own error, before this answer is consulted.
current_handler() {
    duti -x "$1" 2>/dev/null | sed -n 3p
}

# Common development file extensions
EXTENSIONS=(
    # Markdown / Documentation
    .md
    .markdown
    .mdx
    .rst
    .txt
    
    # Python
    .py
    .pyi
    .pyx
    .pyw
    .ipynb
    
    # JavaScript / TypeScript
    .js
    .jsx
    .ts
    .tsx
    .mjs
    .cjs
    
    # Web
    #
    # .html and .htm are deliberately absent, and they are the one exclusion in this list.
    # Both resolve to public.html, and on macOS the handler for public.html is not merely
    # related to your default browser, it is one of the three records that define it, along
    # with the http and https URL schemes, all written together as a group. So asking for it
    # here is asking to become the browser, and macOS stops and asks the user, which is why
    # this step used to raise a change your default browser dialog on every single run.
    #
    # There is no way around it, which was tested rather than assumed. Setting only the
    # viewer role, touching neither scheme, still raised the prompt. No role, flag or
    # ordering avoids it, because the guard is on the setting rather than on how it is
    # reached, and it is deliberate, since silently repointing public.html is how browser
    # hijacking worked.
    #
    # Nothing is lost. Opening an HTML file in an editor never needed the default handler,
    # a path on the command line, a drag onto the dock, or Open With all work untouched.
    .css
    .scss
    .sass
    .less
    .vue
    .svelte
    
    # Data / Config
    .json
    .jsonc
    .json5
    .yaml
    .yml
    .toml
    .xml
    .csv
    
    # Shell
    .sh
    .bash
    .zsh
    .fish
    
    # Ruby
    .rb
    .erb
    .rake
    .gemspec
    
    # Rust
    .rs
    
    # Go
    .go
    .mod
    .sum
    
    # Java / Kotlin
    .java
    .kt
    .kts
    .gradle
    
    # C / C++
    .c
    .h
    .cpp
    .hpp
    .cc
    .cxx
    
    # C#
    .cs
    .csx
    
    # Swift
    .swift
    
    # PHP
    .php
    
    # Lua
    .lua
    
    # Perl
    .pl
    .pm
    
    # R
    .r
    .R
    
    # Scala
    .scala
    .sc
    
    # Elixir / Erlang
    .ex
    .exs
    .erl
    
    # Haskell
    .hs
    .lhs
    
    # Clojure
    .clj
    .cljs
    .cljc
    .edn
    
    # SQL
    .sql
    
    # Docker
    .dockerfile
    
    # Terraform
    .tf
    .tfvars
    
    # GraphQL
    .graphql
    .gql
    
    # Protobuf
    .proto
    
    # Misc config
    .env
    .ini
    .cfg
    .conf
    .config
    .properties
    .editorconfig
    .gitignore
    .gitattributes
    .dockerignore
    .eslintrc
    .prettierrc
    .babelrc
    
    # Diff / Patch
    .diff
    .patch
    
    # Log files
    .log
)

# Three outcomes, not two, and the middle one is why this used to claim fifty five failures
# while exiting zero and saying nothing about any of them.
#
# duti resolves an extension to a uniform type identifier and asks Launch Services to bind the
# handler to that type. macOS only has a real identifier for an extension when some installed
# application declares one, .py to public.python-script and .json to public.json. Where
# nothing declares one it invents a placeholder instead, dyn.ah62d4 and a hash of the
# extension, and Launch Services refuses to attach a default handler to an invented type,
# returning error -50.
#
# That is not this script failing and it is not fixable from here. The type has to come from
# an application declaring it, and an editor listing extensions under CFBundleTypeExtensions,
# which is the legacy mechanism, earns a place in the Open With menu without creating a type
# at all. Zed does exactly that for rs, go and the rest, declaring no UTImportedType or
# UTExportedType of its own, which is why those extensions have nothing to bind to.
#
# So the error is kept rather than sent to /dev/null, since these three cases are only
# distinguishable by reading it, and only the third is a real failure.
#
# The report is a line per extension only on a run that changed something or could not.
# Every other step in setup.sh says "already current" in one line when there is nothing to do,
# and this one used to print a hundred, the same hundred every run, which was half the log of a
# run whose point is to be read. So the loop keeps its per extension lines back, and prints
# them all when at least one extension was moved to this handler, is waiting on a dialog, or
# was refused, and one line when none of that happened. What it asks for does not change, only what it says about it.
BOUND=0
CHANGED=0
UNTYPED=0
REFUSED=0
UNTYPED_LIST=""
PENDING=0
REPORT=""

for ext in "${EXTENSIONS[@]}"; do
    before="$(current_handler "$ext")"
    error="$(duti -s "$BUNDLE_ID" "$ext" all 2>&1)" || true
    after="$(current_handler "$ext")"
    if printf '%s' "$error" | grep -q 'for dyn\.'; then
        REPORT="$REPORT  · $ext, no registered type on this machine
"
        UNTYPED=$((UNTYPED + 1))
        UNTYPED_LIST="$UNTYPED_LIST $ext"
    elif [ "$after" = "$BUNDLE_ID" ]; then
        BOUND=$((BOUND + 1))
        if [ "$before" = "$BUNDLE_ID" ]; then
            REPORT="$REPORT  ✓ $ext, already
"
        else
            REPORT="$REPORT  ✓ $ext, was ${before:-unset}
"
            CHANGED=$((CHANGED + 1))
        fi
    elif [ -n "$error" ]; then
        REPORT="$REPORT  ✗ $ext, $error
"
        REFUSED=$((REFUSED + 1))
    else
        REPORT="$REPORT  ? $ext, still ${before:-unset}, macOS is asking on screen
"
        PENDING=$((PENDING + 1))
    fi
done

if [ "$CHANGED" -eq 0 ] && [ "$REFUSED" -eq 0 ] && [ "$PENDING" -eq 0 ]; then
    echo "$APP_NAME is already the default for $BOUND extension(s), $UNTYPED have no type to bind to"
    exit 0
fi

echo "Setting $APP_NAME ($BUNDLE_ID) as default for development files..."
echo
printf '%s' "$REPORT"
echo
echo "Bound $BOUND extension(s) to $APP_NAME, $CHANGED of them newly"

if [ "$UNTYPED" -gt 0 ]; then
    echo
    echo "$UNTYPED extension(s) have no type for a handler to attach to, which is not a failure:"
    echo "  $(printf '%s' "$UNTYPED_LIST" | sed 's/^ //')"
    echo
    echo "  macOS invents a placeholder type for an extension no installed application"
    echo "  declares, and will not bind a default handler to an invented one. Nothing here"
    echo "  can change that, and installing something that declares the type would."
fi

# Not a failure and not counted as one, since it is a fact about this machine's screen rather
# than about the repository, the same line the dependency check draws for a grant.
if [ "$PENDING" -gt 0 ]; then
    echo
    echo "$PENDING extension(s) are waiting on a dialog. macOS asks before a default handler"
    echo "  changes and duti does not wait for the answer, so choose $APP_NAME in each one and"
    echo "  run this again to see them bound."
fi

if [ "$REFUSED" -gt 0 ]; then
    echo
    echo "$REFUSED extension(s) are not bound to $APP_NAME, listed above" >&2
    exit 1
fi
