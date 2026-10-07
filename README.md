# Dotfiles

Personal dotfiles and machine bootstrap configuration, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick Start

```bash
./setup.sh
```

This runs all setup scripts in sequence. Restart your terminal when done, then run `nvim` to bootstrap LazyVim.

On a machine this repository has not seen before, capture it first, so setup knows what this
machine takes. See [Capturing a machine](#capturing-a-machine).

## Capturing a machine

Machines differ, and `MACHINES` at the repository root says how. It has one default row per
optional piece and rows for each machine that differs, keyed by the machine's local hostname.
The pieces are `mise`, `hammerspoon`, `herdr`, `mole`, `docker`, `vpn` and `tools`. A machine
with no rows gets every default, which keeps its own setup alone and leaves mise off.

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
   changing a row you already set by hand. Nothing is installed or removed, only `MACHINES` is
   written.
4. **Check what was written.**
   ```bash
   git diff MACHINES
   ```
   Edit a row by hand if you want something else. `tools` lists the mise tools this machine
   takes, names from `dotfiles/mise/TOOLS`, alphabetical, comma separated, no spaces, such as
   `node,python,uv`, or `none`. A tool that is not in the catalog yet gets one row there first,
   with its version.
5. **Commit and push**, so every checkout knows this machine.
   ```bash
   git add MACHINES && git commit -m "machines(<name>) capture" && git push
   ```
6. **Apply it.**
   ```bash
   ./setup.sh
   ```
   The first lines it prints are this machine's name and every piece's value. To apply only a
   change to `tools` or to the catalog, `./src/install-mise-tools.sh` is enough.

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

### Stowed Where MACHINES Turns Them On

- hammerspoon, herdr, mise

### Available but Not Stowed

- alacritty, kitty, wezterm (alternative terminals)
