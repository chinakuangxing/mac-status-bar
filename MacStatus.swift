import AppKit
import Darwin

let quotaPath = ProcessInfo.processInfo.environment["MACSTATUS_QUOTA_PATH"]
    ?? NSHomeDirectory() + "/Library/Application Support/MacStatusBar/quota.json"
let appID = "org.example.macstatusbar"

struct Quota {
    var used: Double?
    var observed: Date?
    var reset: Date?
    var minutes: Int = 0
    var stopped = false
    var problem = "用量数据不可用"
    var valid: Bool { used != nil && problem.isEmpty }
    var window: String {
        if minutes == 10080 { return "周额度" }
        if minutes == 300 { return "5小时额度" }
        return minutes > 0 ? "\(minutes)分钟额度" : "额度"
    }
    static func parse(_ data: Data?, now: Date = Date()) -> Quota {
        var q = Quota()
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = root["last_rate"] as? [String: Any],
              let used = r["used_percent"] as? Double, used.isFinite, (0...100).contains(used),
              let timestamp = r["observed_at"] as? String,
              let reset = r["resets_at"] as? Double, reset.isFinite, reset > 0,
              let minutes = r["window_minutes"] as? Int, minutes > 0,
              let source = r["source"] as? String, source == "local-json" else { return q }
        let f = ISO8601DateFormatter()
        var observed = f.date(from: timestamp)
        if observed == nil { f.formatOptions.insert(.withFractionalSeconds); observed = f.date(from: timestamp) }
        guard let observed else { return q }
        q.used = used; q.observed = observed; q.reset = Date(timeIntervalSince1970: reset)
        q.minutes = minutes; q.stopped = (root["quota_stop_latch"] as? [String: Any])?.isEmpty == false
        let age = now.timeIntervalSince(observed)
        q.problem = age < -60 ? "采样时钟异常" : age > 180 ? "用量数据已过期" : reset <= now.timeIntervalSince1970 ? "等待重置后的新数据" : ""
        return q
    }
}

struct Metrics {
    var quota = Quota()
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var memoryUsed: Double?
    var compressed: Double?
    var swapUsed: Double?
    var pressure: Int32 = 0
    var diskTotal: Double?
    var diskFree: Double?
    var memoryPercent: Int? { memoryUsed.map { Int(($0 / memoryTotal * 100).rounded()) } }
    var pressureName: String { pressure == 1 ? "正常" : pressure == 2 ? "偏高" : pressure == 4 ? "严重" : "未知" }
    static func read() -> Metrics {
        var m = Metrics()
        m.quota = Quota.parse(try? Data(contentsOf: URL(fileURLWithPath: quotaPath)))
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            // App memory (anonymous minus purgeable) + wired + physical compressor.
            let pages = max(0, Double(info.internal_page_count) - Double(info.purgeable_count))
                + Double(info.wire_count) + Double(info.compressor_page_count)
            m.memoryUsed = min(m.memoryTotal, pages * page)
            m.compressed = Double(info.compressor_page_count) * page
        }
        var pressureSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &m.pressure, &pressureSize, nil, 0)
        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { m.swapUsed = Double(swap.xsu_used) }
        var fs = statfs()
        if statfs(NSHomeDirectory(), &fs) == 0 {
            m.diskTotal = Double(fs.f_blocks) * Double(fs.f_bsize)
            m.diskFree = Double(fs.f_bavail) * Double(fs.f_bsize)
        }
        return m
    }
    var title: String {
        let q = quota.valid ? "额余\(Int((100 - quota.used!).rounded()))%" : "额度待更新"
        let d = diskFree.map { "盘余\(Int(($0 / 1e9).rounded()))G" } ?? "盘—"
        let ram = memoryPercent.map { "内存\($0)%" } ?? "内存—"
        let alert = pressure >= 2 || (diskFree ?? .infinity) < 20e9 || (quota.valid && quota.used! >= 90) || quota.stopped
        return "\(alert ? "⚠ " : "")\(q)  \(d)  \(ram)"
    }
    func json() -> [String: Any] {
        ["title": title, "quotaUsedPercent": quota.used as Any? ?? NSNull(),
         "quotaValid": quota.valid, "quotaProblem": quota.problem,
         "quotaWindowMinutes": quota.minutes, "quotaObservedAt": quota.observed.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(),
         "quotaStopped": quota.stopped, "diskFreeGB": diskFree.map { $0 / 1e9 } as Any? ?? NSNull(),
         "diskTotalGB": diskTotal.map { $0 / 1e9 } as Any? ?? NSNull(),
         "memoryUsedGiB": memoryUsed.map { $0 / pow(1024,3) } as Any? ?? NSNull(),
         "memoryTotalGiB": memoryTotal / pow(1024,3), "memoryPercent": memoryPercent as Any? ?? NSNull(),
         "memoryPressure": pressureName, "swapUsedGiB": swapUsed.map { $0 / pow(1024,3) } as Any? ?? NSNull()]
    }
}

func gib(_ n: Double?) -> String { n.map { String(format: "%.1f GiB", $0 / pow(1024, 3)) } ?? "未知" }
func gb(_ n: Double?) -> String { n.map { String(format: "%.1f GB", $0 / 1e9) } ?? "未知" }
func dateText(_ d: Date?) -> String {
    guard let d else { return "未知" }
    let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 HH:mm:ss"
    return f.string(from: d)
}

class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class StatusButton: NSButton {
    var metrics = Metrics()
    private var symbols: [String: NSImage] = [:]
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    func update(_ value: Metrics) {
        let changed = metrics.title != value.title || metrics.pressure != value.pressure
            || metrics.quota.stopped != value.quota.stopped
        metrics = value
        title = value.title // Accessible description; draw() uses only icons and numbers.
        setAccessibilityValue(value.title)
        if changed { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark ? NSColor(calibratedWhite: 0.10, alpha: 0.97) : NSColor(calibratedWhite: 0.98, alpha: 0.97)
        base.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let colors: [NSColor] = dark
            ? [NSColor(srgbRed: 0.40, green: 0.86, blue: 0.73, alpha: 1), NSColor(srgbRed: 0.75, green: 0.65, blue: 1, alpha: 1), NSColor(srgbRed: 0.44, green: 0.76, blue: 1, alpha: 1)]
            : [NSColor(srgbRed: 0.02, green: 0.40, blue: 0.31, alpha: 1), NSColor(srgbRed: 0.43, green: 0.28, blue: 0.72, alpha: 1), NSColor(srgbRed: 0.10, green: 0.37, blue: 0.66, alpha: 1)]
        let quotaText: String = metrics.quota.valid ? "\(Int((100.0 - metrics.quota.used!).rounded()))%" : "—"
        let diskText: String = metrics.diskFree.map { "\(Int(($0 / 1e9).rounded()))G" } ?? "—"
        let memoryText: String = metrics.memoryPercent.map { "\($0)%" } ?? "—"
        let values: [String] = [quotaText, diskText, memoryText]
        let names = ["chevron.left.forwardslash.chevron.right", "internaldrive", "memorychip"]
        let warnings = [metrics.quota.stopped || (metrics.quota.valid && metrics.quota.used! >= 90),
                        (metrics.diskFree ?? .infinity) < 20e9, metrics.pressure >= 2]
        for i in 0..<3 {
            let cell = NSRect(x: CGFloat(i) * 68 + 2, y: 2, width: 66, height: 19)
            let accent = warnings[i] ? (dark ? NSColor.systemOrange : NSColor(srgbRed: 0.66, green: 0.29, blue: 0.02, alpha: 1)) : colors[i]
            accent.withAlphaComponent(dark ? 0.12 : 0.07).setFill()
            NSBezierPath(roundedRect: cell, xRadius: 5, yRadius: 5).fill()
            let name = warnings[i] ? "exclamationmark.triangle.fill" : (i == 0 && !metrics.quota.valid ? "clock.arrow.circlepath" : names[i])
            let key = "\(name)-\(i)-\(dark)-\(warnings[i])"
            if symbols[key] == nil, let source = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                symbols[key] = source.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium).applying(NSImage.SymbolConfiguration(paletteColors: [accent])))
            }
            let icon = symbols[key]
            let maxIcon = NSRect(x: cell.minX + 6, y: 5, width: 15, height: 13)
            if let icon {
                let ratio = min(maxIcon.width / icon.size.width, maxIcon.height / icon.size.height)
                let size = NSSize(width: icon.size.width * ratio, height: icon.size.height * ratio)
                icon.draw(in: NSRect(x: maxIcon.midX - size.width / 2, y: maxIcon.midY - size.height / 2, width: size.width, height: size.height))
            }
            let text = NSAttributedString(string: values[i], attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: dark ? NSColor(calibratedWhite: 0.96, alpha: 1) : NSColor(calibratedWhite: 0.13, alpha: 1)])
            text.draw(at: NSPoint(x: cell.minX + 26, y: (bounds.height - text.size().height) / 2))
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            window?.performDrag(with: event)
        } else { super.mouseDown(with: event) }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: StatusPanel!
    var button: StatusButton!
    let menu = NSMenu()
    var metrics = Metrics()
    var timer: Timer?
    var rows: [String: NSMenuItem] = [:]
    var labels: [String: NSTextField] = [:]
    var menuOpen = false
    var refreshCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: appID)
        if siblings.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 206, height: 23), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Mac 状态"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        button = StatusButton(frame: NSRect(x: 0, y: 0, width: 206, height: 23))
        button.isBordered = false
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .labelColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.target = self; button.action = #selector(showMenu)
        button.setAccessibilityLabel("Mac 状态：本地额度、硬盘空间、内存")
        panel.contentView = button
        positionPanel()
        menu.autoenablesItems = false
        menu.delegate = self
        buildMenu()
        refresh()
        panel.orderFrontRegardless()
        timer = Timer(timeInterval: 15, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer!.tolerance = 3
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(positionPanel), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showMenu() }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-render"), CommandLine.arguments.count > index + 1 {
            let destination = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.verifyRender(destination) }
        }
    }
    @objc func positionPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        let leftArea = screen.auxiliaryTopLeftArea
        let rightEdge = leftArea?.maxX ?? (screen.frame.midX - 8)
        let barHeight = max(24, screen.safeAreaInsets.top)
        let x = max(screen.frame.minX + 8, rightEdge - panel.frame.width - 6)
        let y = screen.frame.maxY - barHeight + (barHeight - panel.frame.height) / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    @objc func showMenu() {
        refresh(); updateMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
    }
    // Explicit one-shot QA mode: render this app's own status button, never the desktop.
    func verifyRender(_ destination: String) {
        refresh()
        let directory = URL(fileURLWithPath: destination)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
            button.cacheDisplay(in: button.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("status-button.png"))
        }
        let originalAppearance = button.appearance
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
            button.appearance = NSAppearance(named: appearance)
            button.needsDisplay = true
            if let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                button.cacheDisplay(in: button.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("status-\(name).png"))
            }
        }
        button.appearance = originalAppearance
        button.needsDisplay = true
        var report = metrics.json()
        report["panelVisible"] = panel.isVisible
        report["rightStatusItemsCreated"] = 0
        report["refreshIntervalSeconds"] = 15
        report["refreshCount"] = refreshCount
        report["buttonFrame"] = NSStringFromRect(button.frame)
        report["windowFrame"] = button.window.map { NSStringFromRect($0.frame) } ?? "missing"
        report["screenFrames"] = NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "topSafeArea": String(Double($0.safeAreaInsets.top)), "leftOfCamera": $0.auxiliaryTopLeftArea.map { NSStringFromRect($0) } ?? "none"] }
        updateMenu()
        report["menuTitles"] = menu.items.map { $0.title }
        report["readableRows"] = labels.mapValues { ["text": $0.stringValue, "color": $0.textColor?.description ?? "nil", "fontSize": String(Double($0.font?.pointSize ?? 0))] }
        report["pid"] = ProcessInfo.processInfo.processIdentifier
        report["observedAt"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("ui-probe.json"), options: .atomic)
        }
    }
    func row(_ key: String, _ text: String = "") {
        let r = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 25))
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 16, y: 3, width: 408, height: 20)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        view.addSubview(label); r.view = view
        menu.addItem(r); rows[key] = r; labels[key] = label
    }
    func heading(_ text: String) {
        let key = "heading-" + text
        row(key, text)
        labels[key]?.font = NSFont.boldSystemFont(ofSize: 13)
    }
    func action(_ text: String, _ selector: Selector) {
        let r = NSMenuItem(title: text, action: selector, keyEquivalent: ""); r.target = self; menu.addItem(r)
    }
    func buildMenu() {
        heading("Mac 状态 · 随时看一眼")
        menu.addItem(.separator())
        heading("可选本地额度")
        row("quota"); row("quotaReset"); row("quotaTime"); row("quotaLatch")
        row("quotaNote", "仅显示本地 JSON 提供的单个额度窗口")
        menu.addItem(.separator())
        heading("硬盘 · 主目录所在卷")
        row("disk"); row("diskNote", "显示当前可用空间，不含可清理的缓存")
        menu.addItem(.separator())
        heading("内存")
        row("ram"); row("pressure"); row("swap"); row("compressed")
        row("ramNote", "是否吃紧请结合内存压力；缓存不等于卡顿")
        menu.addItem(.separator())
        row("refreshNote", "轻量模式：每15秒读取 · 点开立即刷新")
        action("打开活动监视器…", #selector(openActivityMonitor))
        action("打开储存空间设置…", #selector(openStorage))
        action("立即重新读取", #selector(refresh))
        action("恢复到摄像头左侧", #selector(positionPanel))
        action("使用说明…", #selector(help))
        menu.addItem(.separator())
        action("退出 Mac 状态", #selector(quit))
    }
    @objc func refresh() {
        refreshCount += 1
        metrics = Metrics.read()
        button.update(metrics)
        button.toolTip = "本地剩余额度 · 硬盘可用空间 · 内存使用率；⌘拖动可挪位置"
        if menuOpen { updateMenu() }
    }
    func updateMenu() {
        let q = metrics.quota
        if q.valid {
            rows["quota"]?.title = "\(q.window)：已用 \(Int(q.used!))% · 剩余 \(Int(100-q.used!))%"
        } else {
            rows["quota"]?.title = q.problem + (q.used.map { "（上次已用 \(Int($0))%）" } ?? "")
        }
        rows["quotaReset"]?.title = "额度重置：\(dateText(q.reset))"
        rows["quotaTime"]?.title = "本地采样：\(dateText(q.observed))"
        rows["quotaLatch"]?.title = q.stopped ? "⚠ 本地数据标记停机；本工具不控制任务" : "来源：可选本地 JSON · 未验证真实性 · 只读"
        rows["disk"]?.title = "可用 \(gb(metrics.diskFree)) / 总容量 \(gb(metrics.diskTotal))"
        rows["ram"]?.title = "已用 \(gib(metrics.memoryUsed)) / \(gib(metrics.memoryTotal))（\(metrics.memoryPercent.map(String.init) ?? "—")%）"
        rows["pressure"]?.title = "内存压力：\(metrics.pressureName)"
        rows["swap"]?.title = "交换空间已用：\(gib(metrics.swapUsed))"
        rows["compressed"]?.title = "压缩内存占用：\(gib(metrics.compressed))"
        for (key, label) in labels { label.stringValue = rows[key]?.title ?? "" }
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; refresh() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
    @objc func openActivityMonitor() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
    @objc func openStorage() { if let u = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(u) } }
    @objc func help() {
        let alert = NSAlert()
        alert.messageText = "顶部三个数怎么看"
        alert.informativeText = "从左到右：绿色代码图标是可选本地剩余额度；紫色硬盘图标是可用GB；蓝色芯片图标是内存使用率。异常项变为橙色警告图标；额度过期显示刷新图标和—。\n\n常驻在摄像头左侧。按住⌘拖动可调整位置；菜单较长时可避让。\n\n每15秒读取本地指标，点开立即刷新；不启动子进程、不请求网络、不调用AI、无动画。额度依赖用户自行提供的本地 JSON；不配置时显示—。\n\n不会安装登录启动。退出菜单结束本程序。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
}

func selfTest() {
    let now = Date(timeIntervalSince1970: 1800000000)
    func payload(_ used: Double = 28, age: Double = 20, reset: Double = 1000, source: String = "local-json", latch: Bool = false) -> Data {
        var obj: [String: Any] = ["last_rate": ["used_percent": used, "observed_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(-age)), "resets_at": now.timeIntervalSince1970 + reset, "window_minutes": 10080, "source": source]]
        if latch { obj["quota_stop_latch"] = ["reason": "test"] }
        return try! JSONSerialization.data(withJSONObject: obj)
    }
    func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    expect(Quota.parse(payload(), now: now).valid, "Fresh valid local quota")
    expect(!Quota.parse(payload(age: 181), now: now).valid, "Stale quota must not look live")
    expect(!Quota.parse(payload(age: -61), now: now).valid, "Future clock")
    expect(!Quota.parse(payload(reset: -1), now: now).valid, "Expired reset")
    expect(!Quota.parse(payload(source: "historical_log"), now: now).valid, "No historical fallback")
    expect(!Quota.parse(payload(101), now: now).valid, "Out of range")
    expect(!Quota.parse(nil, now: now).valid, "Missing file")
    expect(!Quota.parse(Data("{".utf8), now: now).valid, "Corrupt file")
    expect(Quota.parse(payload(100, latch: true), now: now).stopped, "Preserve latch")
    var m = Metrics(); m.quota = Quota.parse(payload(), now: now); m.diskFree = 32e9; m.memoryUsed = m.memoryTotal * 0.7
    expect(m.title == "额余72%  盘余32G  内存70%", "Title meaning")
    m.pressure = 2; expect(m.title.hasPrefix("⚠"), "Pressure warning")
    m.pressure = 1; m.diskFree = 19e9; expect(m.title.hasPrefix("⚠"), "Disk warning")
    m.diskFree = 32e9; m.quota = Quota.parse(payload(90), now: now); expect(m.title.hasPrefix("⚠"), "Quota warning")
    m.quota = Quota.parse(payload(age: 181), now: now); expect(m.title.contains("额度待更新"), "Hide stale percentage")
    expect(!Quota.parse(payload(-1), now: now).valid, "Negative percentage")
    expect(Quota.parse(payload(age: 180), now: now).valid, "Freshness boundary")
    expect(Quota.parse(payload(age: -60), now: now).valid, "Future tolerance boundary")
    let live = Metrics.read()
    expect((live.diskTotal ?? 0) > 0 && (live.diskFree ?? -1) >= 0, "Local disk readable")
    expect(live.memoryTotal > 0 && live.memoryUsed != nil, "Local memory readable")
    print("PASS: 19 quota, display, disk and memory checks")
}

if CommandLine.arguments.contains("--self-test") { selfTest() }
else if CommandLine.arguments.contains("--snapshot") {
    let data = try! JSONSerialization.data(withJSONObject: Metrics.read().json(), options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}

