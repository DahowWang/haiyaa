import AVFoundation
import Cocoa
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("accurateMode") private var accurateMode = false
    @AppStorage("serverURL") private var serverURL = "http://127.0.0.1:5577"
    @State private var serverDraft = ""
    @State private var serverMessage: String?
    @State private var serverError = false
    @State private var loginEnabled = false
    @State private var loginPending = false
    @State private var loginError: String?
    @State private var microphone = false
    @State private var listening = false
    @State private var accessibility = false
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "用得順手就好", subtitle: "辨識方式、快捷鍵和權限，都在這裡。")
                preferences
                server
                permissions
                shortcuts
            }
            .padding(28)
        }
        .tint(Appearance.accent)
        .onAppear { serverDraft = serverURL; refreshStatus() }
        .onReceive(refresh) { _ in refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshStatus() }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("一般", systemImage: "slider.horizontal.3").font(.headline)
            Toggle(isOn: $accurateMode) {
                settingLabel("精準模式", detail: "用兩個模型一起辨識，較準，但要多等約 1 秒")
            }
            .toggleStyle(.switch)
            .tint(Appearance.emphasis)
            Divider()
            Toggle(isOn: Binding(get: { loginEnabled }, set: setLogin)) {
                settingLabel("登入時自動開啟", detail: "登入 Mac 後，Haiyaa 就在選單列等你")
            }
            .toggleStyle(.switch)
            .tint(Appearance.emphasis)
            if loginPending {
                HStack {
                    Text("請到系統設定允許 Haiyaa 登入項目。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("開啟登入項目") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Appearance.error)
            }
        }
        .padding(20).background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var server: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("辨識服務", systemImage: "network").font(.headline)
            Text("辨識服務網址").font(.callout)
            HStack {
                TextField("http://127.0.0.1:5577", text: $serverDraft)
                    .textFieldStyle(.roundedBorder).onSubmit(saveServer)
                Button("儲存", action: saveServer).buttonStyle(HaiyaaPrimaryButtonStyle()).disabled(serverDraft == serverURL)
            }
            Text("改好後，重新開啟 Haiyaa 就會生效。")
                .font(.caption).foregroundStyle(.secondary)
            if let serverMessage {
                Label(serverMessage, systemImage: serverError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(serverError ? Appearance.error : Color.secondary)
            }
        }
        .padding(20).background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("權限", systemImage: "hand.raised").font(.headline)
            permission("麥克風", detail: "錄製你的聲音", granted: microphone, pane: "Privacy_Microphone")
            Divider()
            permission("輸入監控", detail: "接收左 Option 與 Esc 快捷鍵", granted: listening, pane: "Privacy_ListenEvent")
            Divider()
            permission("輔助使用", detail: "將文字貼到目前的游標位置", granted: accessibility, pane: "Privacy_Accessibility")
        }
        .padding(20).background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("快捷鍵", systemImage: "keyboard").font(.headline)
            shortcut("左 Option", text: "點一下開始，再點一下送出")
            shortcut("按住左 Option", text: "超過 1 秒是按住說話，放開送出")
            shortcut("Esc", text: "取消本次錄音")
        }
        .padding(20).background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.body)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permission(_ title: String, detail: String, granted: Bool, pane: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3).foregroundStyle(granted ? Appearance.accent : Appearance.error)
                .accessibilityLabel(granted ? "已允許" : "尚未允許")
            settingLabel(title, detail: detail)
            Spacer()
            Button("開啟設定") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .accessibilityLabel("開啟\(title)設定")
        }
    }

    private func shortcut(_ key: String, text: String) -> some View {
        HStack {
            Text(key).font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Appearance.inset, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 130, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func refreshStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginPending = SMAppService.mainApp.status == .requiresApproval
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        listening = CGPreflightListenEventAccess()
        accessibility = AXIsProcessTrusted()
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "設定登入項目失敗：\(error.localizedDescription)"
        }
        refreshStatus()
    }

    private func saveServer() {
        let value = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            serverError = true
            serverMessage = "請輸入有效的 http 或 https 網址，不含帳密、查詢參數或片段。"
            return
        }
        serverURL = value
        serverDraft = value
        serverError = false
        serverMessage = "已儲存，請重新開啟 Haiyaa。"
    }
}
