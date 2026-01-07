#!/bin/bash
set -e

# Shared file sync utility with backup support
# Usage: sync-files.sh [OPTIONS] CONFIG_FILE
#
# Config format: source_path:dest_path (one per line)
# Source paths relative to repo root, dest paths absolute (can use $HOME)

FORCE=false
REPO_ROOT=""
BACKUP_DIR=""

# Counters
CREATED=0
UNCHANGED=0
SKIPPED=0
UPDATED=0
SKIPPED_FILES=()

usage() {
    echo "Usage: $0 [OPTIONS] CONFIG_FILE"
    echo ""
    echo "Sync files from source to destination based on config file."
    echo ""
    echo "Options:"
    echo "  -f, --force   Overwrite existing files (creates backups first)"
    echo "  -r, --root    Repository root directory (default: auto-detect)"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Config format (one mapping per line):"
    echo "  source/path:destination/path"
    echo ""
    echo "Default behavior:"
    echo "  - Creates new files if they don't exist"
    echo "  - Skips existing files that differ (no overwrite)"
}

create_backup() {
    local file="$1"
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR="$HOME/.mdj-env-setup-backups/$(date +%Y%m%d%H%M%S)"
    fi
    local backup_path="$BACKUP_DIR$file"
    mkdir -p "$(dirname "$backup_path")"
    cp "$file" "$backup_path"
}

sync_file() {
    local src="$1"
    local dest="$2"
    local name="$(basename "$dest")"

    # Ensure destination directory exists
    mkdir -p "$(dirname "$dest")"

    # Handle symlinks - remove and replace with file
    if [[ -L "$dest" ]]; then
        echo "  Removing symlink: $dest"
        rm -f "$dest"
    fi

    if [[ ! -f "$dest" ]]; then
        cp "$src" "$dest"
        echo "  Created: $name"
        ((CREATED++)) || true
    elif diff -q "$src" "$dest" >/dev/null 2>&1; then
        echo "  Unchanged: $name"
        ((UNCHANGED++)) || true
    elif [[ "$FORCE" == true ]]; then
        create_backup "$dest"
        cp "$src" "$dest"
        echo "  Updated: $name (backup created)"
        ((UPDATED++)) || true
    else
        echo "  Skipped: $name (differs, use --force to overwrite)"
        SKIPPED_FILES+=("$dest")
        ((SKIPPED++)) || true
    fi
}

print_summary() {
    echo ""
    echo "=== Summary ==="
    echo "  Created:   $CREATED"
    echo "  Unchanged: $UNCHANGED"
    [[ $UPDATED -gt 0 ]] && echo "  Updated:   $UPDATED"
    [[ $SKIPPED -gt 0 ]] && echo "  Skipped:   $SKIPPED"

    if [[ $SKIPPED -gt 0 ]]; then
        echo ""
        echo "Skipped files (use --force to overwrite):"
        for f in "${SKIPPED_FILES[@]}"; do
            echo "  - $f"
        done
    fi

    if [[ -n "$BACKUP_DIR" ]]; then
        echo ""
        echo "Backups: $BACKUP_DIR"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--root)
            REPO_ROOT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
        *)
            CONFIG_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: CONFIG_FILE required"
    usage
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Auto-detect repo root if not specified
if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(cd "$(dirname "$CONFIG_FILE")/.." && pwd)"
fi

# Process config file
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Parse source:dest
    src_rel="${line%%:*}"
    dest_raw="${line#*:}"

    # Expand $HOME in dest path
    dest="$(eval echo "$dest_raw")"
    src="$REPO_ROOT/$src_rel"

    if [[ ! -f "$src" ]]; then
        echo "  Warning: Source not found: $src"
        continue
    fi

    sync_file "$src" "$dest"
done < "$CONFIG_FILE"

print_summary
