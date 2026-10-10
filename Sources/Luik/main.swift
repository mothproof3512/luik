import AppKit

// Luik runs as an "accessory" app: no Dock icon, just a menu bar item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
