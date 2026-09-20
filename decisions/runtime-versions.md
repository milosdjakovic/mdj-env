# Runtime versions, and the one tool that switches them

Status. mise is declared by the zsh module, installed from the Brewfile, and activated by a
guarded line in `.zshrc.custom`. It replaced fnm, which was a node only switcher and is gone.
No language is configured through it yet and no version is pinned anywhere, because nothing
here has asked for one.

## Now

`mise` covers node, ruby, python and java in one tool, which is the whole reason it is here
rather than four tools. It is declared `optional` by the zsh module and its activation line is
guarded, so a machine without it loses version switching and nothing else. It is in the
Brewfile, so a default install gets it.

Nothing is pinned. There is no `mise.toml` in this repository and no version file in any
project on this machine, so mise is present and idle. That is the intended state until a
project needs a version, at which point the version belongs to that project rather than here.

Java is deliberately unconfigured. The tool can install JDKs and that is why it was chosen over
staying with a node only switcher, but nothing on this machine needs one yet and the Flutter
side has friction worth knowing before starting. The Rejected section has it.

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

**Enabling mise's idiomatic version file support now, 2026-09-20.** Rejected as premature. mise
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
