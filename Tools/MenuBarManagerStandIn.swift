import AppKit

// Stands in for a menu bar manager such as Bartender, Hidden Bar or Ice, for `make menu-bar-check`.
//
// Such a manager hides icons the way this does: it owns an icon and a divider, both with a saved
// place in the menu bar, and stretches the divider until everything to its left is pushed off
// the screen. A status item macOS has no saved place for is put at the far left, so behind the
// divider.
//
// Usage: MenuBarManagerStandIn [seconds to stay]

let defaults = UserDefaults.standard
let names = (icon: "StandInIcon", divider: "StandInDivider")
// Places are kept in order, the smallest furthest right: the icon, then the divider to its left.
defaults.set(100, forKey: "NSStatusItem Preferred Position \(names.icon)")
defaults.set(200, forKey: "NSStatusItem Preferred Position \(names.divider)")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let icon = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
icon.autosaveName = names.icon
icon.button?.title = "Manager"
let divider = NSStatusBar.system.statusItem(withLength: 10_000)
divider.autosaveName = names.divider
divider.button?.title = "|"

func report() {
    let iconFrame = icon.button?.window?.frame ?? .zero
    let dividerFrame = divider.button?.window?.frame ?? .zero
    print("Stand-in manager: icon at x=\(Int(iconFrame.minX)); divider from x=\(Int(dividerFrame.minX)) to x=\(Int(dividerFrame.maxX))")
    fflush(stdout)
}

func leave() -> Never {
    NSStatusBar.system.removeStatusItem(icon)
    NSStatusBar.system.removeStatusItem(divider)
    if let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.arguments.first.map({ URL(fileURLWithPath: $0).lastPathComponent }) {
        defaults.removePersistentDomain(forName: domain)
    }
    exit(0)
}

signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { leave() }
termination.resume()

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 60
DispatchQueue.main.asyncAfter(deadline: .now() + 1) { report() }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { leave() }
app.run()
