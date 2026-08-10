// Report, and optionally ask for, permission to send Apple Events to one application.
//
// macOS gates automation per pair of applications, the one sending and the one being
// driven, and Hammerspoon exposes no binding for reading that state. Performing a real
// event to find out is destructive, because a refusal is remembered forever and macOS then
// never prompts again, so the settings surface must be able to look without touching.
// AEDeterminePermissionToAutomateTarget answers exactly that, and with askUserIfNeeded set
// it is also the documented way to raise the prompt on purpose.
//
// The status returned describes the calling process, which for a helper spawned by
// Hammerspoon is Hammerspoon itself, since macOS attributes automation to the responsible
// parent rather than the immediate binary. That is what makes this readable at all, and it
// is verifiable: this same binary reports granted when run from a terminal that holds the
// grants and notDetermined when run from Hammerspoon, which holds none.
//
// Usage. probe <bundleId> [ask]
// Prints one word on stdout and exits zero. Without "ask" nothing is ever shown to the
// user, so it is safe to call on every settings open.

import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
  print("usage")
  exit(2)
}
let ask = args.count > 2 && args[2] == "ask"

var target = AEAddressDesc()
let bundleID = Array(args[1].utf8)
let created: OSErr = bundleID.withUnsafeBytes { raw in
  AECreateDesc(typeApplicationBundleID, raw.baseAddress, raw.count, &target)
}
guard created == noErr else {
  print("unknown")
  exit(0)
}

let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
AEDisposeDesc(&target)

switch status {
case noErr:
  print("granted")
case OSStatus(-1744):  // errAEEventWouldRequireUserConsent, never asked yet
  print("notDetermined")
case OSStatus(-1743):  // errAEEventNotPermitted, refused and remembered
  print("denied")
case OSStatus(-600):   // procNotFound, the target is not running
  print("notRunning")
case OSStatus(-1728):  // errAENoSuchObject, nothing answers to that bundle id
  print("noTarget")
default:
  print("unknown")
}
