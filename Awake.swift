import Cocoa
import IOKit.pwr_mgt

// Tiny menu bar keep-awake toggle.
// While on, it holds a power assertion that stops the display (and Mac) from
// sleeping due to idleness — the same thing `caffeinate -d` does.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var sleepAssertion: IOPMAssertionID = 0

    private var enabled = false { didSet { apply() } }

    func applicationDidFinishLaunching(_ note: Notification) {
        enabled = true
    }

    func applicationWillTerminate(_ note: Notification) {
        enabled = false
    }

    private func apply() {
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
        if enabled {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Keeping the display awake" as CFString, &sleepAssertion)
        }
        updateIcon()
        buildMenu()
    }

    private func updateIcon() {
        let image = NSImage(systemSymbolName: enabled ? "cup.and.saucer.fill" : "cup.and.saucer",
                            accessibilityDescription: "Keep awake")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !enabled
    }

    private func buildMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: enabled ? "Keeping awake — click to pause" : "Paused — click to keep awake",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() { enabled.toggle() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
