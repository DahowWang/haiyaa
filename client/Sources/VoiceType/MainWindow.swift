import Cocoa
import Combine
import SwiftUI

final class MainWindowController: NSWindowController {
    init() {
        let controller = NSHostingController(rootView: MainView())
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "Haiyaa"
        window.identifier = NSUserInterfaceItemIdentifier("VoiceTypeMainWindow")
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 780, height: 580)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func open() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Destination: String, CaseIterable, Identifiable {
    case home = "首頁", history = "紀錄", dictionary = "詞庫", settings = "設定"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .settings: return "slider.horizontal.3"
        }
    }
}

private struct MainView: View {
    @State private var destination: Destination? = .home
    @StateObject private var history = HistoryStore()
    @StateObject private var dictionary = DictionaryStore()
    private let refresh = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.title2.weight(.semibold)).foregroundStyle(Appearance.accent)
                        .frame(width: 38, height: 38).background(Appearance.inset, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haiyaa").font(.headline)
                        Text("想寫的，說出來就好").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20)
                VStack(spacing: 5) {
                    ForEach(Destination.allCases) { page in
                        Button { destination = page } label: {
                            Label(page.rawValue, systemImage: page.symbol)
                                .font(.body.weight(destination == page ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .foregroundStyle(destination == page ? Appearance.onEmphasis : Color.primary)
                                .background(destination == page ? Appearance.emphasis : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(destination == page ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 7) {
                    Label("左 Option", systemImage: "option").font(.system(.caption, design: .monospaced).weight(.medium))
                    Text("有話想寫，就按一下。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Appearance.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group {
                switch destination ?? .home {
                case .home: HomeView(history: history, showHistory: { destination = .history })
                case .history: HistoryView(history: history)
                case .dictionary: DictionaryView(store: dictionary)
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Appearance.canvas)
            .navigationTitle((destination ?? .home).rawValue)
        }
        .frame(minWidth: 780, minHeight: 580)
        .tint(Appearance.accent)
        .accentColor(Appearance.accent)
        .onAppear { history.refresh() }
        .onReceive(refresh) { _ in
            if NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "VoiceTypeMainWindow" }) { history.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in history.refresh() }
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeView: View {
    @ObservedObject var history: HistoryStore
    let showHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "嗨，想說什麼？", subtitle: "把游標放好，想寫的話就說出來吧。")
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.fill").font(.title3).foregroundStyle(Appearance.accent)
                    Text("點一下左 Option 開始，再點一下送出").font(.callout.weight(.medium))
                    Spacer()
                    Text("⌥").font(.title3).foregroundStyle(.secondary)
                        .frame(width: 34, height: 30).background(Appearance.card, in: RoundedRectangle(cornerRadius: 7))
                }
                .padding(16).background(Appearance.inset, in: RoundedRectangle(cornerRadius: 14))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "今天的語音輸入", value: "\(history.todayCount)", unit: "次", symbol: "sun.max")
                    StatCard(title: "累計語音輸入", value: "\(history.entries.count)", unit: "次", symbol: "waveform")
                    StatCard(title: "累計文字", value: history.totalCharacters.formatted(), unit: "字", symbol: "text.alignleft")
                    StatCard(title: "平均處理時間", value: history.averageTime.map { String(format: "%.1f", $0) } ?? "—",
                             unit: "秒", symbol: "timer")
                }
                HStack(spacing: 16) {
                    Image(systemName: "leaf").font(.title2).foregroundStyle(Appearance.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("估計省下 \(String(format: "%.1f", history.savedMinutes)) 分鐘").font(.headline)
                        Text("以打字每分鐘 40 字、說話每分鐘 150 字估算")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18).background(Appearance.inset, in: RoundedRectangle(cornerRadius: 14))
                HStack {
                    Text("最近紀錄").font(.headline)
                    Spacer()
                    Button("查看全部", action: showHistory).buttonStyle(.plain).foregroundStyle(Appearance.accent)
                }
                if history.entries.isEmpty {
                    HistoryEmptyView(unavailable: history.unavailable, loading: history.isLoading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(history.entries.prefix(5)) { entry in
                            HistoryRow(entry: entry)
                            if entry.id != history.entries.prefix(5).last?.id { Divider().padding(.horizontal, 16) }
                        }
                    }
                    .background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(28)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol).foregroundStyle(Appearance.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Appearance.accent)
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Appearance.border, lineWidth: 0.5))
    }
}

private struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    @State private var search = ""
    private var filtered: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? history.entries : history.entries.filter {
            [$0.final, $0.app, $0.rawA, $0.rawB, $0.dateLabel].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "每一句，都在這裡", subtitle: "剛剛說過的話，可以在這裡找回來、複製再用。")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋文字、App 或時間", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("清除搜尋")
                }
                Divider().frame(height: 16)
                Button { history.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(history.isLoading).help("重新載入紀錄")
            }
            .padding(12).background(Appearance.card, in: RoundedRectangle(cornerRadius: 10))
            Text("\(filtered.count) 筆紀錄").font(.caption).foregroundStyle(.secondary)
            if history.entries.isEmpty {
                HistoryEmptyView(unavailable: history.unavailable, loading: history.isLoading)
                Spacer()
            } else if filtered.isEmpty {
                ContentUnavailableView("找不到符合的紀錄", systemImage: "magnifyingglass", description: Text("試試其他文字或 App 名稱。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry)
                                .background(Appearance.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding(28)
    }
}

private struct HistoryEmptyView: View {
    let unavailable: Bool
    let loading: Bool
    var body: some View {
        ContentUnavailableView {
            Label(loading ? "正在載入紀錄" : unavailable ? "目前無法讀取紀錄" : "來，說說看", systemImage: "waveform")
        } description: {
            Text(loading ? "稍等一下，正在找你說過的話。" : unavailable ? "資料庫可能尚未建立或暫時忙碌，稍後會自動重新載入。" : "把游標放到想輸入的地方，點一下左 Option 就能開始說話。")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(entry.dateLabel)
                        Text("·")
                        Text(entry.app).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(entry.total.map { String(format: "%.1f 秒", $0) } ?? "—")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if !expanded {
                        Text(entry.final.isEmpty ? "（沒有文字）" : entry.final)
                            .font(.body).foregroundStyle(.primary).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("\(entry.dateLabel)，\(entry.app)，\(entry.final)")
            .accessibilityHint(expanded ? "收合細節" : "展開辨識細節")
            if expanded {
                Divider()
                Text(entry.final.isEmpty ? "（沒有文字）" : entry.final).textSelection(.enabled)
                rawText("原始辨識 A", text: entry.rawA)
                rawText("原始辨識 B", text: entry.rawB)
                HStack {
                    Label(entry.usedFallback ? "已退回原始辨識" : "未使用退回結果",
                          systemImage: entry.usedFallback ? "arrow.uturn.backward" : "checkmark.circle")
                        .foregroundStyle(entry.usedFallback ? Appearance.error : Color.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.final, forType: .string)
                        copied = true
                    } label: { Label(copied ? "已複製" : "複製", systemImage: copied ? "checkmark" : "doc.on.doc") }
                }
                .font(.caption)
                VStack(spacing: 7) {
                    timing("錄音長度", seconds: entry.duration)
                    ForEach(entry.timings.keys.sorted(), id: \.self) { key in
                        timing(timingName(key), seconds: entry.timings[key] ?? 0)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func rawText(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(text.isEmpty ? "沒有辨識內容" : text).font(.callout).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Appearance.inset, in: RoundedRectangle(cornerRadius: 8))
    }

    private func timing(_ title: String, seconds: Double) -> some View {
        HStack { Text(title); Spacer(); Text(String(format: "%.2f 秒", seconds)).monospacedDigit() }
    }

    private func timingName(_ key: String) -> String {
        ["asr_a": "模型 A 辨識", "asr_b": "模型 B 辨識", "llm": "文字潤飾", "total": "總處理時間",
         "context": "擷取上下文", "refine": "文字潤飾", "decode": "音訊解碼"][key] ?? "其他階段（\(key)）"
    }
}

private struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @State private var editing: DictionaryLine?
    @State private var showingEditor = false
    @State private var mapping = false
    @State private var correct = ""
    @State private var aliases = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "讓 Haiyaa 更懂你", subtitle: "你的名字、常用的詞，告訴 Haiyaa 怎麼寫。")
                HStack {
                    Label(store.savedAt == nil ? "修改後立即儲存，下次辨識生效" : "已儲存，下次辨識生效", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("重新載入") { store.load() }
                }
                if let error = store.error { errorView(error) }
                dictionarySection(title: "常用詞", subtitle: "常用的人名、品牌與專有名詞", mapping: false)
                dictionarySection(title: "固定誤聽對照", subtitle: "指定正確寫法，讓常見誤聽自動修正", mapping: true)
                Label("原有的 # 註解會保留在詞庫檔案中。", systemImage: "doc.text")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .onAppear { store.load() }
        .sheet(isPresented: $showingEditor) { editor }
    }

    private func dictionarySection(title: String, subtitle: String, mapping: Bool) -> some View {
        let lines = store.document.lines.filter { $0.kind == (mapping ? .mapping : .word) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { edit(nil, mapping: mapping) } label: { Label("新增", systemImage: "plus") }
                    .buttonStyle(HaiyaaPrimaryButtonStyle())
                    .disabled(!store.loaded)
            }
            if lines.isEmpty {
                Text(mapping ? "有哪個詞老是聽錯？在這裡告訴 Haiyaa。" : "加入第一個詞，從你的名字開始。")
                    .foregroundStyle(.secondary).font(.callout).padding(.vertical, 18)
            }
            ForEach(lines) { line in
                HStack(spacing: 12) {
                    Text(line.correct).fontWeight(.medium)
                    if mapping {
                        Image(systemName: "arrow.left").foregroundStyle(.tertiary)
                        Text(line.aliases).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { edit(line, mapping: mapping) } label: { Image(systemName: "pencil") }
                        .help("編輯 \(line.correct)").accessibilityLabel("編輯 \(line.correct)")
                    Button { store.delete(line.id) } label: { Image(systemName: "trash") }
                        .help("刪除 \(line.correct)").accessibilityLabel("刪除 \(line.correct)")
                }
                .padding(.vertical, 5)
                if line.id != lines.last?.id { Divider() }
            }
        }
        .padding(20).background(Appearance.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editing == nil ? (mapping ? "新增誤聽對照" : "新增常用詞") : "編輯詞庫").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text(mapping ? "正確寫法" : "常用詞").font(.callout)
                TextField("例如：Haiyaa", text: $correct).textFieldStyle(.roundedBorder)
            }
            if mapping {
                VStack(alignment: .leading, spacing: 6) {
                    Text("容易誤聽成").font(.callout)
                    TextField("例如：嗨呀、海呀", text: $aliases).textFieldStyle(.roundedBorder)
                    Text("多個誤聽用頓號或逗號分隔。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = store.error { errorView(error) }
            HStack {
                Spacer()
                Button("取消") { showingEditor = false }.keyboardShortcut(.cancelAction)
                Button("儲存") {
                    if store.save(id: editing?.id, correct: correct, aliases: aliases, mapping: mapping) { showingEditor = false }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(HaiyaaPrimaryButtonStyle())
            }
        }
        .padding(24).frame(width: 420)
        .background(Appearance.canvas)
        .tint(Appearance.accent)
    }

    private func errorView(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Appearance.error)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func edit(_ line: DictionaryLine?, mapping: Bool) {
        editing = line
        self.mapping = mapping
        correct = line?.correct ?? ""
        aliases = line?.aliases ?? ""
        store.error = nil
        showingEditor = true
    }
}
