// swift-tools-version:5.9
// The swift chooser's sources built a second way, as a package with no LuaSkin and no Lua, step 0.6
// of docs/PLAN-STANDALONE.md. Hammerspoon's build is unchanged, lib/swiftbuild.lua compiling every
// file in native/ with swiftc as before. This one leaves out the two files that are the Lua seam,
// Lua.swift and Entry.swift, and bridge.h, so what it builds is the panel alone, driven through
// ChooserSource in native/Source.swift. Olm.app is built on this. olm-chooser-smoke shows a list
// from a fake source with no window, test/swiftpackage.sh in the spoon runs it.

import PackageDescription

let package = Package(
  name: "OlmChooser",
  platforms: [.macOS(.v14)],
  products: [.library(name: "OlmChooser", targets: ["OlmChooser"])],
  targets: [
    .target(
      name: "OlmChooser",
      path: "native",
      exclude: ["Lua.swift", "Entry.swift", "bridge.h"],
      // The smoke check reaches the panel's internal types through a testable import, and a
      // plain build compiles a module without the testing entry points it needs.
      swiftSettings: [.unsafeFlags(["-enable-testing"])]
    ),
    .executableTarget(name: "olm-chooser-smoke", dependencies: ["OlmChooser"], path: "smoke"),
  ]
)
