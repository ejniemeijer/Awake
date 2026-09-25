import Cocoa
import IOKit.pwr_mgt

// Tiny menu bar keep-awake toggle.
// While on, it holds a power assertion that stops the display (and Mac) from
// sleeping due to idleness — the same thing `caffeinate -d` does.
// Optionally it also moves the cursor 1px and back after a chosen idle time,
// so apps that watch mouse movement see activity. That needs Accessibility access.

/// A menu row with an icon, title, subtitle and a switch, like Control Center.
final class SwitchRow: NSView {
    let toggle = NSSwitch()
    private let subtitleLabel = NSTextField(labelWithString: "")

    var subtitle: String {
        get { subtitleLabel.stringValue }
        set { subtitleLabel.stringValue = newValue }
    }
    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }

    init(symbol: String, title: String, target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 48))

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        icon.contentTintColor = .labelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor

        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        toggle.controlSize = .small
        toggle.target = target
        toggle.action = action

        let row = NSStackView(views: [icon, text, NSView(), toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.frame = bounds
        row.autoresizingMask = [.width, .height]
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        addSubview(row)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let intervals: [(label: String, short: String, seconds: TimeInterval)] = [
        ("30 seconds", "30 sec", 30), ("1 minute", "1 min", 60), ("2 minutes", "2 min", 120), ("4 minutes", "4 min", 240),
    ]
    private var sleepAssertion: IOPMAssertionID = 0
    private var timer: Timer?

    private var enabled = false { didSet { apply() } }
    private var nudgeCursor = UserDefaults.standard.object(forKey: "nudge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(nudgeCursor, forKey: "nudge"); apply() }
    }
    private var nudgeAfter = UserDefaults.standard.object(forKey: "nudgeAfter") as? TimeInterval ?? 60 {
        didSet { UserDefaults.standard.set(nudgeAfter, forKey: "nudgeAfter"); refreshMenu() }
    }

    private var awakeRow: SwitchRow!
    private var nudgeRow: SwitchRow!
    private let idleItem = NSMenuItem()
    private let accessItem = NSMenuItem()

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
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
        refreshMenu()
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
                            accessibilityDescription: "Awake")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !enabled
    }

    // MARK: Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = 290

        menu.addItem(.sectionHeader(title: "Awake"))
        awakeRow = SwitchRow(symbol: "cup.and.saucer.fill", title: "Keep display awake",
                             target: self, action: #selector(toggleEnabled))
        menu.addItem(viewItem(awakeRow))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Cursor"))
        nudgeRow = SwitchRow(symbol: "cursorarrow.motionlines", title: "Move cursor when idle",
                             target: self, action: #selector(toggleNudge))
        menu.addItem(viewItem(nudgeRow))

        idleItem.image = symbol("timer")
        idleItem.submenu = NSMenu()
        for option in intervals {
            let item = NSMenuItem(title: option.label, action: #selector(pickInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(option.seconds)
            idleItem.submenu?.addItem(item)
        }
        menu.addItem(idleItem)

        accessItem.title = "Allow Accessibility Access…"
        accessItem.subtitle = "Needed to move the cursor"
        accessItem.image = symbol("exclamationmark.triangle.fill", color: .systemOrange)
        accessItem.target = self
        accessItem.action = #selector(requestAccess)
        menu.addItem(accessItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("power")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func refreshMenu() {
        guard awakeRow != nil else { return }
        let trusted = AXIsProcessTrusted()
        let short = intervals.first { $0.seconds == nudgeAfter }?.short ?? "\(Int(nudgeAfter)) sec"

        awakeRow.isOn = enabled
        awakeRow.subtitle = enabled ? "Display won't sleep" : "Normal sleep settings"

        nudgeRow.isOn = nudgeCursor
        nudgeRow.toggle.isEnabled = enabled
        nudgeRow.subtitle = !nudgeCursor ? "Off"
            : !enabled ? "Paused"
            : !trusted ? "Waiting for permission"
            : "Moves 1px after \(short) idle"

        idleItem.isHidden = !nudgeCursor
        idleItem.title = "Idle time: \(short)"
        idleItem.submenu?.items.forEach { $0.state = TimeInterval($0.tag) == nudgeAfter ? .on : .off }

        accessItem.isHidden = !(nudgeCursor && !trusted)
    }

    // Picks up Accessibility permission granted while the app was running.
    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        guard let color else { return image }
        return image?.withSymbolConfiguration(.init(paletteColors: [color]))
    }

    @objc private func toggleEnabled() { enabled = awakeRow.isOn }
    @objc private func toggleNudge() { nudgeCursor = nudgeRow.isOn }
    @objc private func pickInterval(_ sender: NSMenuItem) { nudgeAfter = TimeInterval(sender.tag) }
    @objc private func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
