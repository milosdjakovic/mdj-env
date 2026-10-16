# Olm manifest header

Status. Every plugin manifest declares the `apiVersion` it was written against and an optional
`about` block, both inside `manifest.lua`, and a manifest naming another version is left out
before its code runs.

## Now

`apiVersion` is a required whole number at the top of each manifest. `lib/plugins.lua` checks
it with `checkHeader` while it reads the manifests, comparing it for equality against the
spoon's own `obj.apiVersion` in `Spoons/Olm.spoon/init.lua`. That is the one copy of the
number. The composition root reads it from there for the manifest read and for the registry,
and the dry gate reads the same line and calls the same `checkHeader`, so the live load and the
gate cannot hold two different rules. A manifest that fails the check is left out with one
console line, like a manifest that will not load, and anything that needed it is reported by
the cascade that already handles a missing plugin.

`about` carries `title`, `author`, `version`, `license` and `homepage`, each a string and each
optional. A key outside those five is refused, so a typo is reported where it was written
rather than shown as a blank line on a page that lists plugins. `defaults.description` stays
where it is, since the launcher reads it and a person can override it, and `about` does not
repeat it.

## Rejected

- **A separate `MANIFEST.toml`, `.yaml` or `.json` beside `manifest.lua`.** 2026-10-16. It
  would describe one plugin in two files, which is the arrangement that already lost ten tools
  once in this module, see the hammerspoon `AGENTS.md` under one tool described once.
  Hammerspoon reads JSON and nothing else of the three, the dependency collector reads
  `manifest.lua` through a real Lua interpreter and would need a second reader, and JSON loses
  the comments and local constants manifests use today. A second file earns its place only
  when something outside Lua has to read the plugin list, and nothing does.
- **Relying on the registry's `apiVersion` check.** 2026-10-16. It compares for equality, but
  the registrar stamps the core's own number onto every descriptor it builds, so it can never
  fail for a manifest plugin. It still guards a descriptor assembled anywhere else and is kept
  for that.

## Log

- 2026-10-16 09:10. Milos asked whether plugins should carry author and similar facts in a
  separate manifest file. The answer was one file, with an `about` block and a declared
  `apiVersion` added to `manifest.lua`, and he asked for both. Found while reading the code that
  the only existing version check could not fail for a manifest plugin, and that
  `root/compose.lua` held its own literal `1` beside the spoon's `obj.apiVersion`, two copies of
  one number. The check moved to manifest read, compose now reads the spoon's value, and the
  dry gate reads `init.lua` rather than the literal it used to match in compose. All 35
  manifests under `plugins/` and `host/` carry the header. Verified by the dry gate going from
  35 refusals to zero findings, and by a probe in the running Hammerspoon reading every
  manifest at core version 1 and refusing all 35 at core version 2.
