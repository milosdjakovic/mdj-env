# Developer toolchain, and what the first setup step guarantees

Status. `src/install-xcode-clt.sh` guarantees the Xcode command line tools are installed and
carry an SDK for the running macOS, installs or updates them when not, and stops the run when it
cannot, since that is the exact condition Homebrew checks before any formula without a bottle.

## Now

The step checks `/Library/Developer/CommandLineTools/usr/bin/clang` and an SDK under
`/Library/Developer/CommandLineTools/SDKs` named for the running macOS major version, which is
the name Homebrew's own SDK locator looks for. When both are there it says one line and exits.

When not, it installs headless first. A placeholder file in `/tmp` makes `softwareupdate` list
the command line tools, the newest label is taken, and `sudo softwareupdate -i` installs it,
which is how Homebrew's own installer does it. That needs a password, so it is tried only with a
terminal attached or a sudo ticket held. Apple's dialog through `xcode-select --install` is the
fallback, raised and waited for only with a terminal. If neither leaves the condition met, the
step fails and names what to do, and `setup.sh` stops there.

It never changes what `xcode-select` points at. Homebrew reads the SDK from the command line
tools whenever they are installed, whatever the active developer directory is, so switching it
is not needed for the guarantee, and which Xcode is active is the person's choice.

## Rejected

- **Asking `xcode-select -p` whether any developer directory is active.** Held until
  2026-09-24. An Xcode that predates the running macOS answers yes, and so do command line tools
  installed before a macOS upgrade, while Homebrew refuses both. The step passed and the Homebrew
  step failed two steps later with a message about Xcode.
- **Telling the person to run `sudo xcode-select -s /Library/Developer/CommandLineTools`.**
  2026-09-24. It was suggested for the failing machine and does not reach the cause. Homebrew
  already prefers the command line tools when they exist, so switching fixes nothing when they
  are missing or old, and it changes a setting that is not this step's to change.
- **Only dropping the tap formulas without bottles.** 2026-09-24. fut was dropped for its own
  reason, but ocr is used, a future tap formula would fail the same way, and treesitter and the
  Swift helpers want a current toolchain regardless.
- **Warning and continuing when the condition cannot be met.** The step's behaviour until
  2026-09-24. The Homebrew step then failed on the first formula without a bottle, which is
  fatal there and less legible than failing here.

## Log

- **2026-09-24 15:40.** A second machine on macOS 27 failed the Homebrew step on `ocr` and `fut`,
  both tap formulas that only copy a downloaded binary. Read in Homebrew 7.0.4's source,
  `formula_installer.rb` runs `perform_build_from_source_checks` for any formula it will not pour
  from a bottle, and `check_if_supported_sdk_available` among them is fatal when the toolchain
  has no SDK for the running macOS. `os/mac.rb` takes the SDK from the command line tools
  whenever they are installed and from Xcode only otherwise. The step now guarantees that
  condition. Tested on this machine, where the tools carry the macOS 27 SDK and the step says one
  line, and with the version forced to one no SDK exists for and no terminal, where it stopped
  with the message and exit 1. `softwareupdate -l` with the placeholder listed
  `Command Line Tools for Xcode 27.0-27.0`. The headless install itself was not run, since this
  machine needs none.
