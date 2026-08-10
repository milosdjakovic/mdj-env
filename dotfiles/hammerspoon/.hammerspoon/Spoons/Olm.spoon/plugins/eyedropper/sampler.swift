// Native macOS colour sampler. Shows NSColorSampler, the system eyedropper with
// Apple's own magnifier loupe, and prints the picked colour as hex on stdout,
// then exits. Cancelling the sampler with Escape prints nothing and exits 0. The
// Eyedropper spoon compiles this once, caches the binary, and runs it per pick,
// so the loupe is the real native one and there is no per frame snapshot cost.

import AppKit

let app = NSApplication.shared
// Accessory so no Dock icon or menu bar appears while the sampler is up.
app.setActivationPolicy(.accessory)

let sampler = NSColorSampler()
sampler.show { picked in
    guard let color = picked?.usingColorSpace(.sRGB) else {
        // Cancelled. Nothing chosen, so print nothing and leave.
        exit(0)
    }
    let r = Int((color.redComponent * 255).rounded())
    let g = Int((color.greenComponent * 255).rounded())
    let b = Int((color.blueComponent * 255).rounded())
    print(String(format: "#%02X%02X%02X", r, g, b))
    exit(0)
}

app.run()
