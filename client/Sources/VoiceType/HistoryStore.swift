import Foundation
import Combine
import SQLite3

enum VoiceTypeFiles {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/VoiceType")
}

struct HistoryEntry: Identifiable {
    let id: String
    let createdAt: Date?
    let duration: Double
    let rawA: String
    let rawB: String
    let final: String
    let usedFallback: Bool
    let app: String
    let timings: [String: Double]

    var total: Double? { timings["total"] }
    var characterCount: Int { final.filter { !$0.isWhitespace }.count }
    var dateLabel: String {
        createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "時間不明"
    }
}

enum HistoryReader {
    static func read(at url: URL) throws -> [HistoryEntry] {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        defer { if let database { sqlite3_close(database) } }
        guard result == SQLITE_OK, let database else { throw ReadError.unavailable }
        sqlite3_busy_timeout(database, 250)
        var statement: OpaquePointer?
        let query = "SELECT id, created_at, duration, raw_a, raw_b, final, used_fallback, context, timings FROM history ORDER BY created_at DESC"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw ReadError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        func string(_ index: Int32) -> String {
            guard let value = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: value)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        var entries: [HistoryEntry] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return entries }
            guard step == SQLITE_ROW else { throw ReadError.unavailable }
            let context = (try? JSONSerialization.jsonObject(with: Data(string(7).utf8))) as? [String: Any]
            let rawTimings = (try? JSONSerialization.jsonObject(with: Data(string(8).utf8))) as? [String: Any] ?? [:]
            let timings = rawTimings.compactMapValues { value -> Double? in
                guard let value = value as? Double, value.isFinite, value >= 0 else { return nil }
                return value
            }
            entries.append(HistoryEntry(
                id: string(0), createdAt: fractional.date(from: string(1)) ?? standard.date(from: string(1)),
                duration: sqlite3_column_double(statement, 2), rawA: string(3), rawB: string(4),
                final: string(5), usedFallback: sqlite3_column_int(statement, 6) != 0,
                app: context?["app"] as? String ?? "未知 App", timings: timings
            ))
        }
    }

    enum ReadError: Error { case unavailable }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var unavailable = false
    private let queue = DispatchQueue(label: "tw.mixxin.voicetype.history", qos: .utility)

    var totalCharacters: Int { entries.reduce(0) { $0 + $1.characterCount } }
    var todayCount: Int { entries.filter { $0.createdAt.map(Calendar.current.isDateInToday) ?? false }.count }
    var averageTime: Double? {
        let times = entries.compactMap(\.total)
        return times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
    }
    var savedMinutes: Double { Double(totalCharacters) * (1.0 / 40 - 1.0 / 150) }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        queue.async { [weak self] in
            let result = Result { try HistoryReader.read(at: VoiceTypeFiles.directory.appendingPathComponent("history.db")) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let entries): self.entries = entries; self.unavailable = false
                case .failure: self.entries = []; self.unavailable = true
                }
                self.isLoading = false
            }
        }
    }
}
