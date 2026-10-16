import Foundation

/// 管理本機辨識服務：App 啟動時如果連不到，就自己把 server.py 跑起來；掛了自動重開；App 結束時一起關掉。
/// 伺服器網址指向別台（例如公司共用主機）時，只檢查健康狀態，不會在本機啟動任何東西。
final class ServerManager {
    enum Status { case starting, ready, down(String) }

    var onStatus: ((Status) -> Void)?
    var log: ((String) -> Void)?

    let baseURL: URL
    private let serverDir: String
    private var process: Process?
    private var restarts = 0
    private var healthTimer: Timer?
    private var stopping = false
    private(set) var status: Status = .starting

    init(baseURL: URL, serverDir: String) {
        self.baseURL = baseURL
        self.serverDir = serverDir
    }

    private var isLocal: Bool { ["127.0.0.1", "localhost"].contains(baseURL.host ?? "") }

    func start() {
        set(.starting)
        checkHealth { [weak self] ok in
            guard let self else { return }
            if ok {
                self.log?("辨識服務已在執行，直接使用")
                self.set(.ready)
            } else if self.isLocal {
                self.launch()
            } else {
                self.set(.down("連不到 \(self.baseURL.host ?? "")"))
            }
            self.watch()
        }
    }

    func stop() {
        stopping = true
        healthTimer?.invalidate()
        if let p = process, p.isRunning { p.terminate() }
    }

    private func launch() {
        let python = serverDir + "/.venv/bin/python"
        guard FileManager.default.isExecutableFile(atPath: python) else {
            set(.down("找不到辨識服務：\(python)"))
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-u", serverDir + "/server.py"]
        p.currentDirectoryURL = URL(fileURLWithPath: serverDir)
        // 只傳必要的環境變數：從 Finder／登入項目啟動時 PATH 很陽春，要補上 claude CLI 的位置；
        // 從終端機啟動時又會繼承一堆不相干的變數（例如 Claude Code 自己的），一律不傳，行為才一致
        let inherited = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env: [String: String] = [
            "HOME": home,
            "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "LANG": "zh_TW.UTF-8",
        ]
        for key in ["USER", "LOGNAME", "TMPDIR", "SHELL"] { env[key] = inherited[key] }
        p.environment = env

        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceType/server.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            p.standardOutput = h
            p.standardError = h
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.handleExit(code: proc.terminationStatus) }
        }
        do {
            try p.run()
            process = p
            log?("啟動辨識服務（pid \(p.processIdentifier)）")
            set(.starting)
        } catch {
            set(.down("辨識服務啟動失敗：\(error.localizedDescription)"))
        }
    }

    private func handleExit(code: Int32) {
        process = nil
        guard !stopping else { return }
        log?("辨識服務結束（代碼 \(code)）")
        restarts += 1
        guard restarts <= 5 else {
            set(.down("辨識服務一直異常結束，請看 server.log"))
            return
        }
        set(.down("辨識服務重新啟動中…"))
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts) * 2) { [weak self] in
            self?.launch()
        }
    }

    /// 每 2 秒檢查一次健康狀態，狀態有變才通知
    private func watch() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkHealth { ok in
                guard let self else { return }
                switch (ok, self.status) {
                case (true, .ready): break
                case (true, _):
                    self.restarts = 0
                    self.set(.ready)
                case (false, .ready):
                    self.set(.down("辨識服務沒有回應"))
                default: break
                }
            }
        }
    }

    private func checkHealth(_ done: @escaping (Bool) -> Void) {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"), timeoutInterval: 1.5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && data != nil
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }

    private func set(_ s: Status) {
        status = s
        onStatus?(s)
    }
}
