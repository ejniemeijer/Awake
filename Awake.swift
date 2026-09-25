import Cocoa
import IOKit.pwr_mgt

// Tiny menu bar keep-awake toggle.
// While on, it holds a power assertion that stops the display (and Mac) from
// sleeping due to idleness — the same thing `caffeinate -d` does.
// Optionally it also moves the cursor 1px and back after a chosen idle time,
// so apps that watch mouse movement see activity. That needs Accessibility access.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var sleepAssertion: IOPMAssertionID = 0
    private var timer: Timer?

    private var enabled = false { didSet { apply() } }
    private var nudgeCursor = UserDefaults.standard.object(forKey: "nudge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(nudgeCursor, forKey: "nudge"); apply() }
    }
    private var nudgeAfter = UserDefaults.standard.object(forKey: "nudgeAfter") as? TimeInterval ?? 60 {
        didSet { UserDefaults.standard.set(nudgeAfter, forKey: "nudgeAfter"); buildMenu() }
    }

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
        timer?.invalidate()
        timer = nil

        if enabled {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Keeping the display awake" as CFString, &sleepAssertion)
            if nudgeCursor {
                let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        }
        updateIcon()
        buildMenu()
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        guard idle >= nudgeAfter, AXIsProcessTrusted(),
              let pos = CGEvent(source: nil)?.location else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        for p in [CGPoint(x: pos.x + 1, y: pos.y), pos] {
            CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
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

        let nudge = NSMenuItem(title: "Move cursor 1px when idle", action: #selector(toggleNudge), keyEquivalent: "")
        nudge.target = self
        nudge.state = nudgeCursor ? .on : .off
        menu.addItem(nudge)
        if nudgeCursor {
            for (label, seconds) in [("After 30 seconds idle", 30.0), ("After 1 minute idle", 60),
                                     ("After 2 minutes idle", 120), ("After 4 minutes idle", 240)] {
                let item = NSMenuItem(title: label, action: #selector(pickInterval(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(seconds)
                item.state = nudgeAfter == seconds ? .on : .off
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }
        if nudgeCursor && !AXIsProcessTrusted() {
            let grant = NSMenuItem(title: "Grant Accessibility access…", action: #selector(requestAccess), keyEquivalent: "")
            grant.target = self
            grant.indentationLevel = 1
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func toggleNudge() { nudgeCursor.toggle() }
    @objc private func pickInterval(_ sender: NSMenuItem) { nudgeAfter = TimeInterval(sender.tag) }
    @objc private func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}

extension AppDelegate: NSMenuDelegate {
    // Drop the "Grant Accessibility access…" item once access has been granted.
    func menuDidClose(_ menu: NSMenu) {
        if menu.items.contains(where: { $0.action == #selector(requestAccess) }) && AXIsProcessTrusted() {
            buildMenu()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
