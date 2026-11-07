// swift-tools-version:5.9
// Olm.app, the app of its own docs/PLAN-STANDALONE.md moves Olm into, step 1.1. It builds on the
// swift chooser's package beside the Lua side, lib/chooser/providers/swift, which compiles the
// panel with no Lua, and build.sh beside this file wraps the executable into a bundle. Today it is
// a shell, no Dock icon, one instance, and an answer to olm://ping, docs/PROTOCOL-BRIDGE.md.

import PackageDescription

let package = Package(
  name: "OlmApp",
  platforms: [.macOS(.v14)],
  dependencies: [.package(path: "../lib/chooser/providers/swift")],
  targets: [
    .executableTarget(
      name: "Olm",
      dependencies: ["OlmSearch", .product(name: "OlmChooser", package: "swift")],
      path: "Sources/Olm"
    ),
    // The app's search, ported from the Lua side one part at a time, each part checked against
    // the shared fixtures by olm-fixtures before the app uses it, step 1.3 of the plan.
    .target(name: "OlmSearch", path: "Sources/OlmSearch"),
    .executableTarget(name: "olm-fixtures", dependencies: ["OlmSearch"], path: "Sources/olm-fixtures"),
  ]
)
