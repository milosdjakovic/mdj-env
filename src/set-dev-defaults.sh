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

# Check if duti is installed
if ! command -v duti &> /dev/null; then
    echo "duti is not installed. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "Error: Homebrew is required. Install it from https://brew.sh"
        exit 1
    fi
    brew install duti
fi

# Get bundle identifier for the app
BUNDLE_ID=$(osascript -e "id of app \"$APP_NAME\"" 2>/dev/null)

if [ -z "$BUNDLE_ID" ]; then
    echo "Error: Could not find app \"$APP_NAME\""
    echo "Make sure the app is installed and the name is correct."
    exit 1
fi

echo "Setting $APP_NAME ($BUNDLE_ID) as default for development files..."
echo

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
    .html
    .htm
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

SUCCESS=0
FAILED=0

for ext in "${EXTENSIONS[@]}"; do
    if duti -s "$BUNDLE_ID" "$ext" all 2>/dev/null; then
        echo "  ✓ $ext"
        ((SUCCESS++))
    else
        echo "  ✗ $ext (failed)"
        ((FAILED++))
    fi
done

echo
echo "Done! Set $SUCCESS extensions to open with $APP_NAME"
if [ $FAILED -gt 0 ]; then
    echo "($FAILED extensions failed)"
fi
