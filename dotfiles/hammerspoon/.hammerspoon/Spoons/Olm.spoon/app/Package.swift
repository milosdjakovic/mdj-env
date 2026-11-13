// swift-tools-version:6.0
// Olm.app, the app of its own docs/PLAN-STANDALONE.md moves Olm into, built in the layers
// docs/DESIGN-APP.md names, so a dependency the other way does not build. build.sh beside this file
// wraps the executable into a bundle.
//
//   OlmKit       the vocabulary every part speaks and the ListSource every list answers through
//   OlmSearch    the shared search, ported from lib/chooser/match.lua and rank.lua
//   OlmLook      where a chooser stands, ported from the Lua geometry
//   OlmChooser   the swift chooser's own panel, the package beside the Lua side
//   OlmCore      the stage, the searcher, the look and the shadow
//   OlmBridge    the socket Hammerspoon connects to and the lists it serves, step 2.3
//   plugins      one module each under Plugins/, depending on OlmKit alone
//   Olm          the composition root
//
// The new layers build in Swift 6's language mode, so the compiler checks which thread each piece
// runs on, rule 8 of the plan. The ported search and geometry and the check programs keep Swift 5's,
// since they hold no state across threads and the fixtures pin them.

import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
  name: "OlmApp",
  platforms: [.macOS(.v14)],
  dependencies: [.package(path: "../lib/chooser/providers/swift")],
  targets: [
    .target(name: "OlmKit", path: "Sources/OlmKit"),
    // The app's search, ported from the Lua side one part at a time, each part checked against
    // the shared fixtures by olm-fixtures before the app uses it, step 1.3 of the plan.
    .target(name: "OlmSearch", path: "Sources/OlmSearch", swiftSettings: v5),
    // Where a chooser stands on a screen, ported from the Lua so the app's list stands where the
    // swift chooser's does, test/fixtures/chooser/geometry.json.
    .target(name: "OlmLook", path: "Sources/OlmLook", swiftSettings: v5),
    .target(
      name: "OlmCore",
      dependencies: ["OlmKit", "OlmSearch", "OlmLook", .product(name: "OlmChooser", package: "swift")],
      path: "Sources/OlmCore"
    ),
    // The app's end of the bridge, docs/PROTOCOL-BRIDGE.md, and the launcher Hammerspoon serves over it.
    .target(name: "OlmBridge", dependencies: ["OlmKit", "OlmSearch"], path: "Sources/OlmBridge"),
    // File search, the first native plugin. Its grammar and its index are its own.
    .target(name: "FileSearchPlugin", dependencies: ["OlmKit"], path: "Plugins/FileSearch"),
    .executableTarget(
      name: "Olm",
      dependencies: ["OlmKit", "OlmCore", "OlmBridge", "FileSearchPlugin"],
      path: "Sources/Olm"
    ),
    .executableTarget(name: "olm-fixtures", dependencies: ["OlmKit", "OlmSearch", "OlmLook", "OlmCore", "FileSearchPlugin"],
      path: "Sources/olm-fixtures", swiftSettings: v5),
    // The bridge checked over a socket of its own, a fake Hammerspoon answering it.
    .executableTarget(name: "olm-bridge-check", dependencies: ["OlmKit", "OlmCore", "OlmBridge"],
      path: "Sources/olm-bridge-check", swiftSettings: v5),
    .executableTarget(name: "olm-index-check", dependencies: ["OlmKit", "OlmLook", "OlmCore", "FileSearchPlugin"],
      path: "Sources/olm-index-check", swiftSettings: v5),
  ]
)
