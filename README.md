# Dotfiles

Personal dotfiles and machine bootstrap configuration, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick Start

```bash
./setup.sh
```

This runs all setup scripts in sequence. Restart your terminal when done, then run `nvim` to bootstrap LazyVim.

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
└── .dotfiles/                        # Stow-managed configs
    ├── ghostty/
    ├── tmux/
    ├── nvim/
    ├── zsh/
    ├── hammerspoon/
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
cd .dotfiles
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

### Stowed by Default

- ghostty, tmux, nvim, zsh, hammerspoon

### Available but Not Stowed

- alacritty, kitty, wezterm (alternative terminals)
