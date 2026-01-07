---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git log:*), Bash(git rev-list:*), AskUserQuestion
argument-hint: [message]
description: Create a git commit with conventional commit message
---

# Git Commit

## Step 1: Check Staging Area

```bash
git diff --staged --stat
```

```bash
git status --short
```

**If nothing is staged:**
- Show the user the list of changed files from `git status --short`
- Ask: "Nothing staged. Which files to stage? (all/select/abort)"
  - `all` → run `git add -A`
  - `select` → ask user to specify files/patterns, then run `git add <files>`
  - `abort` → stop and let user handle staging manually
- After staging, re-run `git diff --staged --stat` to confirm

**If files are staged:** proceed to Step 2.

## Step 2: Gather Context

```bash
git rev-list --count HEAD 2>/dev/null || echo "0"
```

```bash
git log --oneline -15 2>/dev/null
```

```bash
git diff --staged
```

## Step 3: Analyze and Generate Message

Using the gathered context:

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

## Step 4: Confirm and Commit

If `$ARGUMENTS` is provided, use that as the commit message directly and skip confirmation.

Otherwise, first output a summary with clear visual separation:

```

Staged: <list of staged files from git diff --staged --stat>

Message:
  <type>(<scope>): <subject>

```

Then use the `AskUserQuestion` tool:
- Question: "Proceed with commit?"
- Header: "Commit"
- Options:
  1. Label: "Accept", Description: "Commit with this message"
  2. Label: "Modify", Description: "Edit the commit message"
  3. Label: "Abort", Description: "Cancel the commit"

Handle response:
- "Accept" → proceed with commit
- "Modify" or "Other" → use their input as the commit message
- "Abort" → stop without committing

Then run:

```bash
git commit -m "<final message>"
```

## Step 5: Verify

```bash
git log --oneline -1
```

Show the created commit to confirm success.
