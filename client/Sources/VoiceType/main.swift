import AVFoundation
import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotkey = HotkeyMonitor()
    private let recorder = Recorder()
    private let hud = HUD()
    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: "最近一次：（還沒有）", action: #selector(copyLast), keyEquivalent: "")
    private var lastText = ""
    private var context: [String: String] = [:]
    private var tapRetry: Timer?
    private var sigterm: DispatchSourceSignal?
    private var mainWindow: MainWindowController?

    private let serverItem = NSMenuItem(title: "辨識服務：啟動中…", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "登入時自動開啟", action: #selector(toggleLogin), keyEquivalent: "")
    private let accurateItem = NSMenuItem(title: "精準模式（雙模型，慢約 1 秒）", action: #selector(toggleAccurate), keyEquivalent: "")
    private var accurate: Bool {
        get { UserDefaults.standard.bool(forKey: "accurateMode") }
        set { UserDefaults.standard.set(newValue, forKey: "accurateMode") }
    }

    /// 伺服器網址可用 `defaults write tw.mixxin.voicetype serverURL http://…` 改成公司主機
    private let server = ServerManager(
        baseURL: URL(string: UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:5577")!,
        serverDir: Bundle.main.object(forInfoDictionaryKey: "VoiceTypeServerDir") as? String ?? ""
    )

    private var serverURL: URL { server.baseURL.appendingPathComponent("dictate") }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        let openItem = NSMenuItem(title: "開啟 Haiyaa…", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        stateItem.isEnabled = false
        serverItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(serverItem)
        lastItem.target = self
        menu.addItem(lastItem)
        menu.addItem(.separator())
        for (title, action) in [("編輯個人詞庫…", #selector(editDictionary)),
                                ("開啟紀錄資料夾", #selector(openData)),
                                ("開啟權限設定…", #selector(openPermissions))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        accurateItem.target = self
        accurateItem.state = accurate ? .on : .off
        menu.addItem(accurateItem)
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束 Haiyaa", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        setState(.idle)

        server.log = { [weak self] msg in self?.log(msg) }
        server.onStatus = { [weak self] st in
            switch st {
            case .starting: self?.serverItem.title = "辨識服務：載入模型中…"
            case .ready: self?.serverItem.title = "辨識服務：就緒"
            case .down(let msg): self?.serverItem.title = "辨識服務：" + msg
            }
        }
        server.start()

        // 被 kill／登出時也要先關掉辨識服務，不然會留下舊版服務佔著連接埠
        signal(SIGTERM, SIG_IGN)
        let sig = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sig.setEventHandler { NSApp.terminate(nil) }
        sig.resume()
        sigterm = sig

        hud.levelProvider = { [weak self] in self?.recorder.level ?? 0 }
        hotkey.log = { [weak self] msg in self?.log(msg) }
        // 麥克風真的收到聲音才提示「可以說了」，USB 麥克風冷啟動會慢幾百毫秒
        recorder.onFirstAudio = { [weak self] latency in
            NSSound(named: "Pop")?.play()
            self?.hud.markReady()
            self?.log(String(format: "麥克風就緒：%.2f 秒", latency))
        }
        hotkey.onPress = { [weak self] in self?.begin() }
        hotkey.onRelease = { [weak self] in self?.finish() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
        hotkey.onHandsFree = { [weak self] in self?.setState(.handsFree) }
        requestPermissions()
    }

    /// 三個權限：麥克風（錄音）、輸入監控（聽快捷鍵）、輔助使用（讀上下文、送 Cmd+V）。
    /// 缺哪個就跳系統詢問；全部到齊才開始監聽，沒到齊就每 2 秒檢查一次。
    private func missingPermissions() -> [String] {
        var missing: [String] = []
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { missing.append("麥克風") }
        if !CGPreflightListenEventAccess() { missing.append("輸入監控") }
        if !AXIsProcessTrusted() { missing.append("輔助使用") }
        return missing
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        checkPermissions()
        tapRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    private func checkPermissions() {
        let missing = missingPermissions()
        writeStatus(["missing_permissions": missing, "checked_at": ISO8601DateFormatter().string(from: Date())])
        guard missing.isEmpty else {
            setState(.error("缺少權限：" + missing.joined(separator: "、") + "（點「開啟權限設定…」）"))
            return
        }
        tapRetry?.invalidate()
        tapRetry = nil
        if hotkey.start() {
            hotkeyReady = true
            setState(.idle)
            writeStatus(["missing_permissions": [String](), "hotkey": "running",
                         "checked_at": ISO8601DateFormatter().string(from: Date())])
        } else {
            setState(.error("快捷鍵監聽啟動失敗，請結束後重開 Haiyaa"))
        }
    }

    /// 狀態寫到 status.json，方便從外部檢查（權限、快捷鍵是否啟動）
    private func writeStatus(_ extra: [String: Any]) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceType")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: extra, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("status.json"))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    /// 一般 App 的選單：沒有「編輯」選單的話，詞庫頁的文字欄位不能用 ⌘C／⌘V
    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let host = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            host.submenu = menu
            main.addItem(host)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        submenu("Haiyaa", [
            item("關於 Haiyaa", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("隱藏 Haiyaa", #selector(NSApplication.hide(_:)), "h"),
            item("結束 Haiyaa", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("編輯", [
            item("還原", Selector(("undo:")), "z"),
            item("重做", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("剪下", #selector(NSText.cut(_:)), "x"),
            item("拷貝", #selector(NSText.copy(_:)), "c"),
            item("貼上", #selector(NSText.paste(_:)), "v"),
            item("全選", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("視窗", [
            item("關閉視窗", #selector(NSWindow.performClose(_:)), "w"),
            item("縮到最小", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        return main
    }

    func applicationWillTerminate(_ note: Notification) {
        server.stop()
    }

    @objc private func toggleAccurate() {
        accurate.toggle()
        accurateItem.state = accurate ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        accurateItem.state = accurate ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openMainWindow() {
        if mainWindow == nil { mainWindow = MainWindowController() }
        mainWindow?.open()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            setState(.error("設定登入項目失敗：\(error.localizedDescription)"))
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func editDictionary() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceType/dictionary.txt")
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openPermissions() {
        let missing = missingPermissions()
        let pane = missing.contains("輔助使用") ? "Privacy_Accessibility"
            : missing.contains("輸入監控") ? "Privacy_ListenEvent" : "Privacy_Microphone"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    // MARK: - 錄音流程

    private func begin() {
        do {
            try recorder.start()
        } catch {
            setState(.error("麥克風啟動失敗：\(error.localizedDescription)"))
            return
        }
        setState(.recording)
        warmServer()
        context = [:]
        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = ContextCapture.capture()
            DispatchQueue.main.async { self.context = ctx }
        }
    }

    /// 通知辨識服務先熱身，等使用者講完時模型已經在 GPU 上待命
    private func warmServer() {
        var req = URLRequest(url: server.baseURL.appendingPathComponent("warm"), timeoutInterval: 2)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req).resume()
    }

    private func cancel() {
        guard recorder.isRecording else { return }
        _ = recorder.stop()
        setState(.idle)
    }

    private func finish() {
        guard recorder.isRecording else { return }
        let (wav, seconds) = recorder.stop()
        log(String(format: "錄到 %.2f 秒音訊", seconds))
        guard seconds >= 0.3 else { setState(.idle); return }
        if case .ready = server.status {} else {
            setState(.error("辨識服務還沒準備好（\(serverItem.title)）"))
            return
        }
        NSSound(named: "Bottle")?.play()
        setState(.processing)

        var req = URLRequest(url: serverURL, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "audio_b64": wav.base64EncodedString(),
            "context": context,
            "accurate": accurate,
        ])
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async { self.handle(data: data, error: error) }
        }.resume()
    }

    private func handle(data: Data?, error: Error?) {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            setState(.error("連不到辨識服務：\(error?.localizedDescription ?? "回應格式錯誤")"))
            return
        }
        if let err = obj["error"] as? String {
            setState(.error(err))
            return
        }
        let text = (obj["text"] as? String) ?? ""
        setState(.idle)
        guard !text.isEmpty else { return }
        lastText = text
        lastItem.title = "最近一次：" + (text.count > 40 ? String(text.prefix(40)) + "…" : text)
        Inserter.insert(text)  // 跟 Typeless 一樣貼上就結束，不另外顯示完成提示
    }

    // MARK: - 選單列

    private enum State { case idle, recording, handsFree, processing, error(String) }

    private func setState(_ s: State) {
        let (symbol, label): (String, String) = {
            switch s {
            case .idle: return ("mic", "想說話時，點一下左 Option 開始，再點一下送出")
            case .handsFree: return ("mic.fill", "我在聽（免持）…點一下左 Option 送出，Esc 取消")
            case .recording: return ("mic.fill", "我在聽…放開送出")
            case .processing: return ("ellipsis.circle", "正在轉成文字…")
            case .error(let msg): return ("exclamationmark.triangle", msg)
            }
        }()
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.contentTintColor = {
            switch s {
            case .recording: return Appearance.accentNS
            case .handsFree: return Appearance.handsFreeNS
            default: return nil
            }
        }()
        stateItem.title = label
        log("state: \(label)")
        switch s {
        case .idle: hud.hide()
        case .recording: hud.showRecording(handsFree: false)
        case .handsFree: hud.showRecording(handsFree: true)
        case .processing: hud.showProcessing()
        case .error(let msg): if hotkeyReady { hud.showError(msg) }
        }
    }

    private var hotkeyReady = false

    /// 客戶端紀錄：~/Library/Application Support/VoiceType/client.log
    private func log(_ msg: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceType/client.log")
        let line = ISO8601DateFormatter().string(from: Date()) + " " + msg + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }

    @objc private func copyLast() {
        guard !lastText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
    }

    @objc private func openData() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceType")
        NSWorkspace.shared.open(url)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 跟 Typeless 一樣出現在 Dock；點 Dock 圖示打開主視窗
app.setActivationPolicy(.regular)
app.mainMenu = AppDelegate.makeMainMenu()
app.run()
