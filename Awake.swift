import Cocoa
import IOKit.pwr_mgt
import os

private let log = Logger(subsystem: "local.awake", category: "cursor")

// Tiny menu bar keep-awake toggle.
// While on, it holds a power assertion that stops the display (and Mac) from
// sleeping due to idleness — the same thing `caffeinate -d` does.
// Optionally it also moves the cursor after a chosen idle time — a 1px nudge or a
// smooth glide across the screen — so apps that watch mouse movement see activity.
// That needs Accessibility access.

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
    private let speeds: [(label: String, seconds: TimeInterval)] = [("Slow", 3), ("Medium", 1.5), ("Fast", 0.6)]
    private var sleepAssertion: IOPMAssertionID = 0
    private var timer: Timer?
    private var glideTimer: Timer?

    private var enabled = false { didSet { apply() } }
    private var nudgeCursor = UserDefaults.standard.object(forKey: "nudge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(nudgeCursor, forKey: "nudge"); apply() }
    }
    private var nudgeAfter = UserDefaults.standard.object(forKey: "nudgeAfter") as? TimeInterval ?? 60 {
        didSet { UserDefaults.standard.set(nudgeAfter, forKey: "nudgeAfter"); refreshMenu() }
    }
    private var glide = UserDefaults.standard.bool(forKey: "glide") {
        didSet { UserDefaults.standard.set(glide, forKey: "glide"); refreshMenu() }
    }
    private var glideDuration = UserDefaults.standard.object(forKey: "glideDuration") as? TimeInterval ?? 1.5 {
        didSet { UserDefaults.standard.set(glideDuration, forKey: "glideDuration"); refreshMenu() }
    }

    private var awakeRow: SwitchRow!
    private var nudgeRow: SwitchRow!
    private let idleItem = NSMenuItem()
    private let styleItem = NSMenuItem()
    private let speedItem = NSMenuItem()
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
        stopGlide()

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
        guard idle >= nudgeAfter, glideTimer == nil, let pos = cursorLocation() else { return }
        guard AXIsProcessTrusted() else {
            log.notice("Idle \(Int(idle), privacy: .public)s but no Accessibility access; not moving")
            return
        }
        log.notice("Idle \(Int(idle), privacy: .public)s; \(self.glide ? "gliding" : "nudging", privacy: .public)")
        if glide {
            startGlide(from: pos)
        } else {
            moveCursor(to: CGPoint(x: pos.x + 1, y: pos.y))
            moveCursor(to: pos)
        }
    }

    /// Glides the cursor along a gentle curve to a random point on its current display.
    /// Stops as soon as you move the mouse yourself.
    private func startGlide(from start: CGPoint) {
        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(start, 1, &displayID, &count)
        let bounds = CGDisplayBounds(displayID).insetBy(dx: 80, dy: 80)
        let end = CGPoint(x: .random(in: bounds.minX...bounds.maxX), y: .random(in: bounds.minY...bounds.maxY))

        // Control point off to one side of the straight line gives a natural arc.
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let bend = CGFloat.random(in: -0.3...0.3)
        let control = CGPoint(x: mid.x - (end.y - start.y) * bend, y: mid.y + (end.x - start.x) * bend)

        let duration = glideDuration
        let began = Date()
        var previous = start
        var last = start
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            // The reported position can lag a frame behind, so only treat it as the user
            // taking over when it's away from both of the last two points we moved to.
            if let now = self.cursorLocation(),
               hypot(now.x - last.x, now.y - last.y) > 4, hypot(now.x - previous.x, now.y - previous.y) > 4 {
                log.notice("Mouse moved by user; glide stopped")
                self.stopGlide()
                return
            }
            let progress = min(Date().timeIntervalSince(began) / duration, 1)
            let e = CGFloat(progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2)
            let u = 1 - e
            previous = last
            last = CGPoint(x: u * u * start.x + 2 * u * e * control.x + e * e * end.x,
                           y: u * u * start.y + 2 * u * e * control.y + e * e * end.y)
            self.moveCursor(to: last)
            if progress >= 1 { self.stopGlide() }
        }
        RunLoop.main.add(t, forMode: .common)
        glideTimer = t
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
    }

    private func cursorLocation() -> CGPoint? { CGEvent(source: nil)?.location }

    private func moveCursor(to point: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
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

        styleItem.image = symbol("scribble.variable")
        styleItem.submenu = NSMenu()
        for (title, tag) in [("Nudge 1px", 0), ("Glide across screen", 1)] {
            let item = NSMenuItem(title: title, action: #selector(pickStyle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            styleItem.submenu?.addItem(item)
        }
        menu.addItem(styleItem)

        speedItem.image = symbol("gauge.with.dots.needle.50percent")
        speedItem.submenu = NSMenu()
        for (index, option) in speeds.enumerated() {
            let item = NSMenuItem(title: option.label, action: #selector(pickSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            speedItem.submenu?.addItem(item)
        }
        menu.addItem(speedItem)

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
            : glide ? "Glides after \(short) idle" : "Moves 1px after \(short) idle"

        idleItem.isHidden = !nudgeCursor
        idleItem.title = "Idle time: \(short)"
        idleItem.submenu?.items.forEach { $0.state = TimeInterval($0.tag) == nudgeAfter ? .on : .off }

        styleItem.isHidden = !nudgeCursor
        styleItem.title = "Movement: \(glide ? "Glide" : "Nudge 1px")"
        styleItem.submenu?.items.forEach { $0.state = ($0.tag == 1) == glide ? .on : .off }

        let speed = speeds.first { $0.seconds == glideDuration }?.label ?? "Medium"
        speedItem.isHidden = !(nudgeCursor && glide)
        speedItem.title = "Speed: \(speed)"
        speedItem.submenu?.items.forEach { $0.state = speeds[$0.tag].seconds == glideDuration ? .on : .off }

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
    @objc private func pickStyle(_ sender: NSMenuItem) { glide = sender.tag == 1 }
    @objc private func pickSpeed(_ sender: NSMenuItem) { glideDuration = speeds[sender.tag].seconds }
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
