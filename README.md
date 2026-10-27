# Dotfiles

Personal dotfiles and machine bootstrap configuration, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick Start

```bash
./setup.sh
```

This runs all setup scripts in sequence. Restart your terminal when done, then run `nvim` to bootstrap LazyVim.

Run from a terminal, it asks for your password once, before the first step, and nothing later
asks again. Near the end it walks through every permission macOS keeps for a person to give,
such as Accessibility for Hammerspoon or Input Monitoring for kanata. For each one still missing
it says in one line what to do, opens the exact System Settings list, shows the program in Finder
when it has to be dragged into the list, and waits until the permission is given, however long
that takes, so the run confirms it and no second run is needed. Enter skips one, and anything
skipped is repeated in the closing notes. Hammerspoon reloads itself once its Accessibility
permission arrives, so its keys work straight away. Run without a terminal, nothing opens and
those notes are all it leaves.

To start it from a shell that has no terminal of its own, such as Claude's, use
`./src/open-in-terminal.sh ./setup.sh`, which opens a Terminal window running it.

On a machine this repository has not seen before, capture it first, so setup knows what this
machine takes. See [Capturing a machine](#capturing-a-machine).

## Capturing a machine

Machines differ, and the `machines/` directory at the repository root says how. Its `default`
folder has one default row per optional piece, and each machine that differs has a folder of its
own, named by the machine's local hostname, with a `pieces` file of the rows that differ. The
pieces are `mise`, `hammerspoon`, `herdr`, `mole`, `docker`, `vpn`, `tools` and `kanata`. A machine
with no rows gets every default, which keeps its own setup alone and leaves mise and kanata off.

Do this once on every machine, and again whenever a machine changes.

1. **Get the repository up to date.**
   ```bash
   cd ~/Development/personal/mdj-env && git pull
   ```
2. **Check the machine's name.**
   ```bash
   scutil --get LocalHostName
   ```
   If it is generic, such as `MacBook-Pro`, another machine may share it. Rename the Mac in
   System Settings, General, Sharing, Local hostname. On a Mac you cannot rename, add
   `export MDJ_MACHINE=Some-Unique-Name` to that machine's `~/.zshrc`, open a new terminal, and
   use that name from here on.
3. **Run capture in a terminal.**
   ```bash
   ./src/machine.sh capture
   ```
   It shows each piece, what it found on this machine, and the value that suggests. Answer each
   question. Enter takes the answer in capitals, which is yes for a new proposal and no for
   changing a row you already set by hand. Nothing is installed or removed, only
   `machines/<name>/pieces` is written.
4. **Check what was written.**
   ```bash
   git diff machines
   ```
   Edit a row by hand if you want something else. `tools` lists the mise tools this machine
   takes, names from `dotfiles/mise/TOOLS`, alphabetical, comma separated, no spaces, such as
   `node,python,uv`, or `none`. A tool that is not in the catalog yet gets one row there first,
   with its version.
5. **Commit and push**, so every checkout knows this machine.
   ```bash
   git add machines && git commit -m "machines(<name>) capture" && git push
   ```
6. **Apply it.**
   ```bash
   ./setup.sh
   ```
   The first lines it prints are this machine's name and every piece's value. To apply only a
   change to `tools` or to the catalog, `./src/install-mise-tools.sh` is enough.

Capture records what a machine has, not what you want it to have. To give a machine a piece it
does not have yet, such as kanata or mise, see the next section.

## Giving a machine its own Hyper app keys and display profiles

A machine with no files of its own gets `machines/default/hammerspoon-apps.lua`, which holds only
apps every machine has, the ones macOS ships and the ones the Brewfile installs, and
`machines/default/hammerspoon-displays.lua`, which holds no display profile.

1. **Capture what it has now** into files of its own.
   ```bash
   ./src/setup-hammerspoon-apps.sh --capture
   ```
   This writes `machines/<name>/hammerspoon-apps.lua` and `hammerspoon-displays.lua`, each
   only where the machine has none yet. Each replaces its default whole, so keep the lines it
   starts with. Delete a captured file you have nothing to add to, and the default applies.
2. **Add this machine's keys** to that file, such as `["hyper+G"] = "apptoggler.GoogleChat"`,
   the name from `dotfiles/hammerspoon/.hammerspoon/config/apps.lua`. An app whose bundle id
   differs on this machine, as every Chrome web app does, goes under `apps`, the id from
   `osascript -e 'id of app "Google Chat"'`. A display profile goes under `profiles` in the
   displays file, a name and the `displayplacer ...` line `displayplacer list` prints last, and
   the default file's header says how matching works.
3. **Apply it.** Hammerspoon reloads by itself when the file changes.
   ```bash
   ./src/setup-hammerspoon-apps.sh
   ```
4. **Commit and push it.** `./setup.sh` applies it from then on.

Change these files, never the copies in `~/.hammerspoon`. A copy edited by hand is left alone and
reported, and `./src/setup-hammerspoon-apps.sh --discard` overwrites it once the change is moved
or not wanted.

## Giving a machine an optional piece

kanata is the example, since it is off by default and capture never offers it on a machine
that does not already run it.

1. **Write the row.**
   ```bash
   ./src/machine.sh set kanata on
   ```
2. **Commit and push it**, so every checkout knows.
   ```bash
   git add machines && git commit -m "machines(<name>) kanata is on" && git push
   ```
3. **Apply only that piece, from a terminal.**
   ```bash
   ./setup.sh --only kanata
   ```
   It asks for your password once. It installs the packages and links the config, then runs the
   kanata step and walks the three permissions kanata needs. For each one, the matching System
   Settings list opens. For the two that need it, the kanata binary is shown in Finder to drag
   in, and the step waits until the permission is given. Enter skips one. `./src/setup-kanata.sh --dry-run`
   shows everything the kanata step would do first, changing nothing.

`tools` takes a list rather than on or off, `./src/machine.sh set tools node,python,uv`, and
`./src/install-mise-tools.sh` applies it.

When a machine's rows were written somewhere else first, from another machine or by hand, run
the steps in a different order. Pull, run `./setup.sh` so the machine gets what its rows ask for,
then capture. Capture then finds the pieces installed and agrees with the rows, and where it
still finds something else it asks with no as the answer Enter gives, so the rows stay. Commit
and push only if it wrote anything.

Running capture again on an unchanged machine says "Nothing to change" and writes nothing. To
read one value, `./src/machine.sh get <piece>`. Switching a piece off never removes anything a
machine already has, that is always done by hand.

## Structure

```
.mdj-env/
├── setup.sh                          # Main orchestrator
├── Brewfile                          # Homebrew packages
├── src/                              # Modular setup scripts
│   ├── install-homebrew.sh           # Homebrew installation
│   ├── install-homebrew-packages.sh  # brew bundle
│   ├── install-ohmyzsh.sh            # oh-my-zsh framework
│   ├── install-ohmyzsh-plugins.sh    # zsh plugins
│   ├── install-tmux-plugins.sh       # TPM plugins
│   ├── setup-stow-dotfiles.sh        # GNU stow operations
│   ├── setup-zshrc.sh                # .zshrc configuration
│   └── set-dev-defaults.sh           # File type associations
└── dotfiles/                         # Stow-managed configs
    ├── ghostty/
    ├── tmux/
    ├── nvim/
    ├── zsh/
    ├── hammerspoon/
    ├── claude/
    ├── alacritty/
    ├── kitty/
    └── wezterm/
```

## Scripts

### Setup Scripts (src/)

| Script | Purpose |
|--------|---------|
| `install-homebrew.sh` | Installs Homebrew if not present |
| `install-homebrew-packages.sh` | Installs packages from Brewfile |
| `install-ohmyzsh.sh` | Installs oh-my-zsh framework |
| `install-ohmyzsh-plugins.sh` | Installs zsh-autosuggestions, fast-syntax-highlighting, fzf-tab |
| `install-tmux-plugins.sh` | Installs tmux plugins via TPM |
| `setup-stow-dotfiles.sh` | Symlinks dotfiles to home directory |
| `setup-zshrc.sh` | Configures .zshrc with Powerlevel10k |
| `set-dev-defaults.sh` | Sets default app for dev file types |
| `setup-grants.sh` | Opens where each missing permission is given and waits until it is given or Enter is pressed, with a terminal, or leaves a closing note |
| `machine.sh` | Reads and writes which optional pieces this machine takes, `get`, `set` and `capture` |
| `open-in-terminal.sh` | Opens a Terminal window running a command of this repository, for a step a person has to sit through |
| `setup-kanata.sh` | Installs the Karabiner driver kanata needs and runs both as root daemons, where the kanata piece is on, with `--dry-run` and `--upgrade` |
| `setup-macos-shortcuts.sh` | Turns off the macOS keyboard shortcuts that take a chord Olm uses, Show Help menu on Command and ? today, where the hammerspoon piece is on |

All scripts are idempotent (safe to re-run) and support both Apple Silicon and Intel Macs.

### Running Individual Scripts

```bash
# Run a specific setup step
./src/install-ohmyzsh-plugins.sh

# Set default editor for dev files
./src/set-dev-defaults.sh "Zed"
./src/set-dev-defaults.sh "Visual Studio Code"
```

## Manual Stow Usage

To selectively stow configurations:

```bash
cd dotfiles
stow tmux           # Just tmux config
stow -t ~ nvim      # Neovim config
stow -t ~ alacritty # Alternative terminal
```

## What Gets Installed

### Homebrew Packages

- **Terminal tools:** git, stow, tmux, tpm, neovim, duti
- **Modern CLI:** zoxide, atuin, eza, bat, fzf, fd, ripgrep, yazi, lazygit
- **Shell:** powerlevel10k
- **Fonts:** MesloLGS Nerd Font
- **Apps:** Ghostty, Hammerspoon

### Stowed on Every Machine

- ghostty, tmux, nvim, zsh, claude, lf, lazygit

### Stowed Where The Machine Turns Them On

- hammerspoon, herdr, mise, kanata

### Available but Not Stowed

- alacritty, kitty, wezterm (alternative terminals)
