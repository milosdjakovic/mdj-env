---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git log:*), Bash(git rev-list:*)
argument-hint: [message]
description: Create a git commit with conventional commit message
---

# Git Commit

## Step 1: Gather Context

Run these commands in order:

```bash
# Check if this is initial commit
git rev-list --count HEAD 2>/dev/null || echo "0"
```

```bash
# Get commit history for scope patterns (skip if initial)
git log --oneline -15 2>/dev/null
```

```bash
# Show what's staged
git diff --staged --stat
```

```bash
# Show detailed staged changes
git diff --staged
```

```bash
# Show working tree status
git status --short
```

## Step 2: Analyze and Generate Message

Using the output from Step 1:

### Conventional Commit Format

```
type(scope): subject
```

### Types
- `feat` - new feature or capability
- `fix` - bug fix
- `refactor` - code restructuring without behavior change
- `docs` - documentation changes
- `style` - formatting, whitespace, no code change
- `test` - adding or updating tests
- `chore` - maintenance, dependencies, tooling
- `perf` - performance improvement

### Scope Rules

**IMPORTANT: Use domain/business scope, NOT technical scope.**

Good (domain-focused):
- `feat(auth): add password reset flow`
- `fix(checkout): resolve cart total calculation`
- `feat(inventory): add low stock alerts`
- `refactor(billing): simplify invoice generation`

Bad (too technical):
- `feat(api): add endpoint` → use the domain it serves
- `fix(component): update state` → use the feature it belongs to
- `refactor(utils): clean helpers` → use the domain using them

To determine scope:
1. Look at commit history from Step 1 for existing scope patterns
2. Identify the domain/feature area the changes belong to
3. Match existing scopes when working in same area
4. If changes span multiple domains, use the primary one

### Initial Commit Handling

If `git rev-list --count HEAD` returned "0" or failed:
- Use `chore: initial commit` for boilerplate/setup
- Use `feat: initial commit` with description if functional code

### Message Rules

1. Subject under 50 characters
2. Present tense imperative: "add" not "added"
3. No period at end
4. Lowercase (except proper nouns)

## Step 3: Confirm and Commit

If `$ARGUMENTS` is provided, use that as the commit message directly.

Otherwise, present the generated message and ask: "Commit with this message? (y/n/edit)"

Then run:

```bash
git commit -m "type(scope): subject"
```

## Step 4: Verify

```bash
git log --oneline -1
```

Show the created commit to confirm success.
