import Cocoa
import IOKit.pwr_mgt

// Tiny menu bar mouse jiggler.
// - Tells macOS there is user activity (resets the idle timer, keeps display awake).
// - Optionally nudges the cursor 1px and back, so apps that watch mouse movement
//   (Teams, Slack, ...) see activity too. Nudging needs Accessibility permission.
// - Only acts when you've been idle for at least the chosen interval.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var sleepAssertion: IOPMAssertionID = 0
    private var activityAssertion: IOPMAssertionID = 0

    private var enabled = false { didSet { apply() } }
    private var interval: TimeInterval = UserDefaults.standard.object(forKey: "interval") as? TimeInterval ?? 60 {
        didSet { UserDefaults.standard.set(interval, forKey: "interval"); apply() }
    }
    private var nudgeCursor: Bool = UserDefaults.standard.object(forKey: "nudge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(nudgeCursor, forKey: "nudge"); buildMenu() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        enabled = true
    }

    func applicationWillTerminate(_ note: Notification) {
        enabled = false
    }

    private func apply() {
        timer?.invalidate()
        timer = nil
        releaseSleepAssertion()

        if enabled {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Jiggler is active" as CFString, &sleepAssertion)
            let t = Timer(timeInterval: min(interval, 15), repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        updateIcon()
        buildMenu()
    }

    private func releaseSleepAssertion() {
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        guard idle >= interval else { return }
        jiggle()
    }

    private func jiggle() {
        IOPMAssertionDeclareUserActivity("Jiggler" as CFString, kIOPMUserActiveLocal, &activityAssertion)

        guard nudgeCursor, AXIsProcessTrusted(),
              let pos = CGEvent(source: nil)?.location else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        for p in [CGPoint(x: pos.x + 1, y: pos.y), pos] {
            CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    private func updateIcon() {
        let name = enabled ? "cursorarrow.motionlines" : "cursorarrow"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Jiggler")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !enabled
    }

    private func buildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: enabled ? "Jiggling — click to pause" : "Paused — click to start",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "When idle for", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (label, seconds) in [("30 seconds", 30.0), ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300)] {
            let item = NSMenuItem(title: label, action: #selector(pickInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(seconds)
            item.state = interval == seconds ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let nudge = NSMenuItem(title: "Nudge cursor (1px)", action: #selector(toggleNudge), keyEquivalent: "")
        nudge.target = self
        nudge.state = nudgeCursor ? .on : .off
        menu.addItem(nudge)
        if nudgeCursor && !AXIsProcessTrusted() {
            let grant = NSMenuItem(title: "Grant Accessibility access…", action: #selector(requestAccess), keyEquivalent: "")
            grant.target = self
            grant.indentationLevel = 1
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jiggler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func pickInterval(_ sender: NSMenuItem) { interval = TimeInterval(sender.tag) }
    @objc private func toggleNudge() { nudgeCursor.toggle() }
    @objc private func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}

extension AppDelegate: NSMenuDelegate {
    // Refresh so the Accessibility item disappears once access is granted.
    func menuNeedsUpdate(_ menu: NSMenu) {}
    func menuWillOpen(_ menu: NSMenu) {
        let needsGrant = menu.items.contains { $0.action == #selector(requestAccess) }
        if needsGrant == AXIsProcessTrusted() { DispatchQueue.main.async { self.buildMenu() } }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
