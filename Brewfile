# An optional piece's lines install only on a machine MACHINES turns it on for, asked through
# src/machine.sh, its one reader. A line switched off is only not installed, never removed.
def on?(key)
  system(File.join(__dir__, "src", "machine.sh"), "on", key.to_s)
end

# Terminal tools
brew "duti"
brew "git"
brew "stow"
brew "tmux"
brew "tpm"
brew "neovim"
brew "zoxide"
brew "atuin"
brew "herdr" if on?(:herdr)
brew "eza"
brew "bat"
brew "fzf"
brew "fd"
brew "ripgrep"
brew "jq"
brew "lf"
brew "trash"
brew "lazygit"
brew "chafa"
brew "displayplacer"
brew "ffmpeg"
brew "libqalculate"
brew "lua"
brew "mise" if on?(:mise)
brew "mole" if on?(:mole)

# Third party taps, for a tool with no formula in core
tap "schappim/ocr"
brew "schappim/ocr/ocr"

# Shell
brew "powerlevel10k"

# Fonts
cask "font-meslo-lg-nerd-font"

# Apps
cask "docker-desktop" if on?(:docker)
cask "ghostty"
cask "hammerspoon" if on?(:hammerspoon)
cask "obsidian"
