# Runtime versions, and the one tool that switches them

Status. On a machine that `MACHINES` turns mise on for, mise manages every language runtime, python, ruby, node, go and rust,
plus uv itself, from a global config in its own stow package, `dotfiles/mise`. A project
overrides any of them with its own pin. uv may only use the interpreters mise installed.

## Now

mise is optional per machine, off by default, and on here. Where it is off nothing is stowed
or installed for it and the shell does not activate it, since activation keys on the config
file existing rather than on the binary. `decisions/machine-profiles.md` has the mechanism.

`dotfiles/mise/.config/mise/config.toml` lists one default version per language, and
`src/install-mise-tools.sh` installs whatever it lists that is missing, after stow and never
moving a version already present. Each default is the major or minor that was in use when mise
took over, so the switch changed nothing a script could notice. Python lists three versions,
3.14 as the default and 3.13 and 3.12 beside it, because projects here pin both and uv can only
reach an interpreter mise put on PATH.

Version files that a cloned repository carries, `.python-version`, `.ruby-version`, `.nvmrc` and
`.node-version`, plus go's, are honoured without a `mise.toml`. Rust is left to rustup, which
mise drives and which reads `rust-toolchain.toml` itself.

uv keeps every job it had, projects, lockfiles, venvs, `uv run` and `uv tool`. Two environment
variables in the same config stop it downloading or preferring an interpreter of its own, so the
machine has one source of Python rather than two.

What macOS ships stays, `/usr/bin/python3` and the `java` stub, and loses only PATH order. What
Homebrew installs as a dependency of another formula stays too, since that formula keeps using
it privately, which is why `python@3.13`, `python@3.14`, `node` and `ruby` are still in the
Cellar. Only the leaves that mise replaced were removed.

Java is still deliberately unconfigured, and the Rejected section says why.

## Rejected

**Keeping fnm, 2026-09-20.** Rejected because it answers one language. The machine needs node,
ruby, python and eventually java, and four single purpose switchers is the outcome this avoids.
fnm was declared optional and kept out of the Brewfile on 2026-09-14 as one of four optional
backends, on the reasoning that a fresh machine has no business getting a node version manager
it never asked for. That rejection no longer holds, and this is why. mise is not the backend of
one feature, it is the only deliberate answer this repository has to which runtime versions a
machine has, and today there is none.

**Removing fnm on its own, before adopting a replacement, 2026-09-20.** Rejected and worth
recording, because it was nearly done. fnm's line carried the guard and the comment explaining
it, and that guard is the lesson mise's line needs, since mise's own documentation gives its
activation line unguarded. Removing fnm first would have deleted the working example in the
same week the replacement needed it. The guard moved across in the same change instead.

**Leaving the runtime versions to Homebrew, 2026-09-20.** Rejected once it was measured. node,
ruby and python were all on this machine already, and all three only as transitive dependencies
of other formulae. None was a leaf, none was in the Brewfile, and nothing declared any of them,
so the versions in use were whatever some unrelated tool dragged in and they moved whenever that
tool was upgraded. That is not a runtime story, it is an accident that had not caused trouble
yet.

**asdf, 2026-09-20.** Rejected for speed and shape. It is the most mature of the four and has by
far the largest plugin ecosystem, and it resolves every tool call through a shim where mise
updates PATH once at the prompt. Reopen if mise's wider surface becomes a liability, since asdf
stays narrowly a version manager and mise also does environment variables and project tasks.

**proto, 2026-09-20.** Rejected as too small and too tied to moonrepo. It fits naturally inside
that toolchain and is the least essential of the four outside it.

**vfox, 2026-09-20.** Rejected, though it was the closest call. It names Flutter directly as a
managed language where mise does not, which is genuinely interesting here, and its other
differentiator is real Windows support, which is worth nothing on a Mac. Managing the Flutter
SDK is a different question from managing the JDK, so it was not enough. Reopen if Flutter SDK
switching turns out to matter more than JDK coverage.

**Configuring java now, 2026-09-20.** Rejected because there is no toolchain to configure. Java
is absent, `/usr/libexec/java_home` finds nothing, and Android Studio, the Android SDK, Flutter
and Gradle are all absent too. Building setup machinery for a toolchain that does not exist is
the ceremony the root guidance warns about.

The friction to know about when it does exist, since it is Flutter's and not mise's. Flutter's
own tool prefers the JDK bundled inside Android Studio over `JAVA_HOME`, reported in flutter
issues 108804 and 121501, so a mise managed JDK can be silently ignored. The workaround is
pinning it explicitly with `flutter config --jdk-dir` pointed at what `mise where java` reports,
and that flag name is reported rather than quoted from Flutter's own reference, which returned
not found when fetched. React Native is unaffected, it goes through Gradle directly and reads
`JAVA_HOME` the ordinary way. Android Studio keeps its own separate Gradle JDK setting, so an
IDE build and a terminal build can quietly disagree.

**Enabling mise's idiomatic version file support now, 2026-09-20.** Reopened 2026-10-06, see
the log. Rejected as premature. mise
reads `.nvmrc`, `.node-version`, `.ruby-version` and `.python-version`, but each language has to
be turned on explicitly and all of them are off by default. There is no such file in any project
on this machine, so enabling them today configures nothing. It will matter the first time a
cloned repository carries one, and the symptom then is mise ignoring a file that looks like it
should work.

## Log

**2026-09-14 22:04.** fnm, mullvad, ivpn and macshot left the Brewfile together at `5040676`,
all four optional, all the backend of a feature rather than the feature itself. Their origins
became `manual`, which is the supported way to say a mapped tool has no Brewfile line rather
than a way around the rule, and the declarations stayed so an absent one is still reported as a
warning. fnm needed more than a moved origin, because it was the one of the four that was
required and unguarded, and `.zshrc.custom` eval'd it on every shell start beside atuin and
zoxide.

**2026-09-20 10:05.** Measured before deciding. No version manager of any kind was installed, no
`mise`, `asdf`, `proto`, `vfox`, `rbenv`, `pyenv`, `jenv` or `sdk`. No `.tool-versions`,
`.nvmrc`, `.node-version`, `.ruby-version`, `.python-version` or `mise.toml` existed anywhere
under `~/Development`. So the migration cost was zero and the decision was about what to adopt
rather than what to move.

**2026-09-20 10:10.** fnm removed entirely, mise adopted, in one change. The guard moved to the
mise line and the comment beside it now states the rule without the archaeology, since that is
what this file is for. The word fnm appears nowhere in the repository any more except here.

Not tested at any point, mise actually installing a runtime of any language, because none was
wanted yet. The first `mise use` of anything is still owed, and the GraalVM question is open,
since mise's java page says GraalVM is unsupported while its own metadata crawler lists GraalVM
distributions. One command settles it when it matters, `mise ls-remote java | grep -i graal`.

**2026-10-06 14:19.** Reversed the stance that versions belong only to projects, at the user's
request for one place to manage python, ruby, rust and go. The 2026-09-20 reasoning was that no
project needed a version, and measuring again showed that was no longer true and that the gap
had been filled by accident instead. Python came from four sources at once, Homebrew's 3.12,
3.13 and 3.14, uv's own downloads of 3.12.11 and 3.13.7, a pipx venv for poetry, and macOS. go,
rustup and uv were Homebrew leaves nothing declared, and cargo was not on PATH at all because
Homebrew's rustup is keg only. `vicert/canvas-medical/canvas-plugins` carries a `.python-version`
of 3.13, so idiomatic version files were turned on for python, ruby, node and go.

A new `mise` stow package holds the global config, and a setup step installs it. The config
directory is folded into this checkout on purpose and carries no `NO-FOLD`, since mise keeps its
state and installs under `~/.local` and the only file it writes here is the config itself, which
`mise use -g` should land in the repository.

The first attempt set only `UV_PYTHON_DOWNLOADS=never`, and `uv run` still chose uv's own
3.13.7 over mise's 3.14 on PATH, since uv prefers a build it manages whenever one exists.
`UV_PYTHON_PREFERENCE=only-system` closed it, verified by `uv run` reporting the mise
interpreter. That limit in turn means a pinned version has to exist in mise, which is why 3.13
and 3.12 sit in the global list. Verified that canvas-plugins resolves to 3.13.16 and fumage's
uv finds 3.12.15.

Installing rust through mise ran rustup, which updated the existing stable toolchain from 1.95.0
to 1.99.0. That is the one version this change moved, and it was not intended.

Removed from Homebrew, each with no dependents, `go`, `rustup`, `uv`, `python@3.12` and
`python-tk@3.14`. Not removed and still owed. uv's own interpreters under
`~/.local/share/uv/python` and the `~/.local/bin/python3.13` link, because the `canvas` uv tool
and the venvs of canvas-plugins, fumage, canvas and anthropic-academy point at the 3.13.7 build
and would break until each is recreated. poetry exists twice, as a Homebrew leaf and in a pipx
venv on Homebrew's 3.13, and pipx itself is a Homebrew leaf. Three venvs under
`personal/education` already point at Homebrew Cellar versions that no longer exist.

**2026-10-06 14:55.** mise became optional per machine through `MACHINES`, off by default,
because a machine with its own pyenv or nvm must not be taken over. The shell guard moved from
the binary to `~/.config/mise/config.toml`, since a machine can have mise installed and still
not want this repository's runtimes acting on every `.nvmrc` it meets.
