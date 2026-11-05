import Cocoa
import ServiceManagement
import UniformTypeIdentifiers

// Rules live in ~/.config/linkrouter/rules.json and are re-read on every link.
// First matching rule wins; a rule may set `app` (sender bundle ID), `domain`, or both.
struct Rule: Codable {
    var app: String?
    var domain: String?
    var browser: String
}

struct Config: Codable {
    var fallback: String
    var rules: [Rule]
}

let defaultConfig = Config(
    fallback: "com.apple.Safari",
    rules: [])

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/linkrouter/rules.json")

func loadConfig() -> (Config, String?) {
    guard let data = try? Data(contentsOf: configURL) else {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(defaultConfig).write(to: configURL)
        return (defaultConfig, nil)
    }
    do {
        return (try JSONDecoder().decode(Config.self, from: data), nil)
    } catch {
        return (defaultConfig, "rules.json is invalid, using defaults")
    }
}

func matches(_ rule: Rule, sender: String?, host: String?) -> Bool {
    if let app = rule.app, app != sender { return false }
    if let d = rule.domain?.lowercased() {
        guard let h = host?.lowercased(), h == d || h.hasSuffix("." + d) else { return false }
    }
    return rule.app != nil || rule.domain != nil
}


let ownBundleID = Bundle.main.bundleIdentifier ?? "me.juanvelasco.linkrouter"

func appName(_ id: String) -> String {
    if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
        return FileManager.default.displayName(atPath: u.path)
    }
    return id
}

func installedBrowsers() -> [String] {
    let urls = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
    let ids = urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { $0 != ownBundleID }
    return Array(Set(ids)).sorted { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }
}

func saveConfig(_ cfg: Config) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? enc.encode(cfg).write(to: configURL, options: .atomic)
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class EditorController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    var config = defaultConfig
    let rowsStack = NSStackView()
    let fallbackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let colWidths: [CGFloat] = [22, 190, 170, 16, 160, 22]

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 440),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "LinkRouter Rules"
        window.isReleasedWhenClosed = false
        buildLayout()
    }

    func show() {
        config = loadConfig().0
        rebuild()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func label(_ s: String, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = bold ? .boldSystemFont(ofSize: 11) : .systemFont(ofSize: 13)
        l.textColor = bold ? .secondaryLabelColor : .labelColor
        return l
    }

    func fixed<T: NSView>(_ v: T, _ w: CGFloat) -> T {
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
    }

    func buildLayout() {
        let content = window.contentView!

        let fbRow = NSStackView(views: [label("Open links in"), fixed(fallbackPopup, 180), label("unless a rule below matches")])
        fbRow.spacing = 8
        fallbackPopup.target = self
        fallbackPopup.action = #selector(fallbackChanged)

        let header = NSStackView(views: [
            fixed(label("", bold: true), colWidths[0]),
            fixed(label("FROM APP", bold: true), colWidths[1]),
            fixed(label("ON SITE", bold: true), colWidths[2]),
            fixed(label("", bold: true), colWidths[3]),
            fixed(label("OPEN IN", bold: true), colWidths[4]),
        ])
        header.spacing = 8

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // Flipped container so rows sit at the top of the scroll area, not the bottom.
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(rowsStack)
        scroll.documentView = doc
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: clip.topAnchor),
            doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: doc.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            rowsStack.trailingAnchor.constraint(lessThanOrEqualTo: doc.trailingAnchor),
        ])

        let add = NSButton(title: "Add Rule", target: self, action: #selector(addRule))
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        let hint = label("Rules are checked top to bottom; the first match wins. Changes save automatically.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        let footer = NSStackView(views: [add, hint])
        footer.spacing = 12

        let main = NSStackView(views: [fbRow, header, scroll, footer])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 10
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: main.widthAnchor),
        ])
    }

    func persist() { saveConfig(config) }

    func rebuild() {
        let browsers = installedBrowsers()

        fallbackPopup.removeAllItems()
        for id in Set(browsers + [config.fallback]).sorted(by: { appName($0) < appName($1) }) {
            let item = NSMenuItem(title: appName(id), action: nil, keyEquivalent: "")
            item.representedObject = id
            fallbackPopup.menu!.addItem(item)
        }
        selectItem(fallbackPopup, representing: config.fallback)

        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if config.rules.isEmpty {
            rowsStack.addArrangedSubview(label("No rules yet. Everything opens in the browser above."))
        }
        for (i, rule) in config.rules.enumerated() {
            rowsStack.addArrangedSubview(makeRow(i, rule, browsers))
        }
    }

    func selectItem(_ p: NSPopUpButton, representing id: String?) {
        if let id, let idx = p.menu!.items.firstIndex(where: { ($0.representedObject as? String) == id }) {
            p.selectItem(at: idx)
        } else {
            p.selectItem(at: 0)
        }
    }

    func makeRow(_ i: Int, _ rule: Rule, _ browsers: [String]) -> NSView {
        let up = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Move up")!,
                          target: self, action: #selector(moveUp(_:)))
        up.isBordered = false
        up.tag = i
        up.isEnabled = i > 0

        let appPop = NSPopUpButton(frame: .zero, pullsDown: false)
        appPop.tag = i
        appPop.target = self
        appPop.action = #selector(appChanged(_:))
        let any = NSMenuItem(title: "Any app", action: nil, keyEquivalent: "")
        any.tag = 0
        appPop.menu!.addItem(any)
        appPop.menu!.addItem(.separator())
        var ids = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }.compactMap { $0.bundleIdentifier })
        ids.remove(ownBundleID)
        ids.formUnion(config.rules.compactMap { $0.app })
        for id in ids.sorted(by: { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }) {
            let item = NSMenuItem(title: appName(id), action: nil, keyEquivalent: "")
            item.representedObject = id
            item.tag = 1
            appPop.menu!.addItem(item)
        }
        appPop.menu!.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: nil, keyEquivalent: "")
        other.tag = -1
        appPop.menu!.addItem(other)
        selectItem(appPop, representing: rule.app)

        let domain = NSTextField()
        domain.placeholderString = "any site, e.g. meet.google.com"
        domain.stringValue = rule.domain ?? ""
        domain.tag = i
        domain.delegate = self

        let arrow = label("→")

        let brPop = NSPopUpButton(frame: .zero, pullsDown: false)
        brPop.tag = i
        brPop.target = self
        brPop.action = #selector(browserChanged(_:))
        for id in Set(browsers + [rule.browser]).sorted(by: { appName($0) < appName($1) }) {
            let item = NSMenuItem(title: appName(id), action: nil, keyEquivalent: "")
            item.representedObject = id
            brPop.menu!.addItem(item)
        }
        selectItem(brPop, representing: rule.browser)

        let del = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete rule")!,
                           target: self, action: #selector(deleteRule(_:)))
        del.isBordered = false
        del.tag = i

        let views: [NSView] = [up, appPop, domain, arrow, brPop, del]
        let row = NSStackView(views: zip(views, colWidths).map { fixed($0, $1) })
        row.spacing = 8
        return row
    }

    // MARK: actions

    @objc func fallbackChanged() {
        if let id = fallbackPopup.selectedItem?.representedObject as? String {
            config.fallback = id
            persist()
        }
    }

    @objc func addRule() {
        let b = installedBrowsers().first { $0 != config.fallback } ?? config.fallback
        config.rules.append(Rule(app: nil, domain: nil, browser: b))
        persist()
        rebuild()
    }

    @objc func deleteRule(_ s: NSButton) {
        config.rules.remove(at: s.tag)
        persist()
        rebuild()
    }

    @objc func moveUp(_ s: NSButton) {
        guard s.tag > 0 else { return }
        config.rules.swapAt(s.tag, s.tag - 1)
        persist()
        rebuild()
    }

    @objc func browserChanged(_ s: NSPopUpButton) {
        if let id = s.selectedItem?.representedObject as? String {
            config.rules[s.tag].browser = id
            persist()
        }
    }

    @objc func appChanged(_ s: NSPopUpButton) {
        let i = s.tag
        switch s.selectedItem?.tag {
        case 0:
            config.rules[i].app = nil
        case -1:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.prompt = "Choose"
            if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
                config.rules[i].app = id
            }
        default:
            config.rules[i].app = s.selectedItem?.representedObject as? String
        }
        persist()
        rebuild()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        let v = f.stringValue.trimmingCharacters(in: .whitespaces)
        config.rules[f.tag].domain = v.isEmpty ? nil : v
        persist()
    }
}

final class Delegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let editor = EditorController()
    var lastRoute = "No links routed yet"
    let lastItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "LinkRouter")
        img?.isTemplate = true
        statusItem.button?.image = img

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(statusLine)
        menu.addItem(lastItem)
        menu.addItem(.separator())
        for (title, sel) in [("Edit Rules…", #selector(openEditor)), ("Open Rules File…", #selector(editRules))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LinkRouter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        _ = loadConfig() // creates the default file on first run
        if CommandLine.arguments.contains("--edit") { editor.show() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let (cfg, err) = loadConfig()
        statusLine.title = err ?? "\(cfg.rules.count) rule(s) loaded"
        lastItem.title = lastRoute
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func editRules() {
        _ = loadConfig()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", configURL.path]
        try? p.run()
    }

    @objc func openEditor() { editor.show() }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s) else { return }
        let (cfg, _) = loadConfig()

        var sender: String?
        if let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value {
            sender = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        let target = cfg.rules.first { matches($0, sender: sender, host: url.host) }?.browser ?? cfg.fallback

        let ws = NSWorkspace.shared
        guard let appURL = ws.urlForApplication(withBundleIdentifier: target)
                ?? ws.urlForApplication(withBundleIdentifier: cfg.fallback) else { return }
        lastRoute = "Last: \(url.host ?? s) → \(appURL.deletingPathExtension().lastPathComponent)"
        ws.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
