import Foundation
import Combine

struct DictionaryLine: Identifiable {
    enum Kind { case preserved, word, mapping }
    let id = UUID()
    var kind: Kind
    var original: String
    var correct: String
    var aliases: String
    var edited = false

    var serialized: String {
        guard edited else { return original }
        return kind == .mapping ? "\(correct)：\(aliases)" : correct
    }
}

/// 未編輯的行逐字保留，包含註解、空白與原本使用的分隔符號。
struct DictionaryDocument {
    var lines: [DictionaryLine]
    private var newline: String
    private var trailingNewline: Bool

    init(text: String) {
        newline = text.contains("\r\n") ? "\r\n" : "\n"
        trailingNewline = text.hasSuffix("\n")
        var source = text.components(separatedBy: newline)
        if trailingNewline { source.removeLast() }
        lines = source.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                return DictionaryLine(kind: .preserved, original: line, correct: "", aliases: "")
            }
            if let separator = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                return DictionaryLine(kind: .mapping, original: line,
                                      correct: String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces),
                                      aliases: String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
            }
            return DictionaryLine(kind: .word, original: line, correct: trimmed, aliases: "")
        }
    }

    var text: String { lines.map(\.serialized).joined(separator: newline) + (trailingNewline ? newline : "") }

    static func normalizedAliases(_ text: String) -> String {
        text.components(separatedBy: CharacterSet(charactersIn: "、,，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "、")
    }
}

final class DictionaryStore: ObservableObject {
    @Published private(set) var document = DictionaryDocument(text: "")
    @Published private(set) var loaded = false
    @Published var error: String?
    @Published private(set) var savedAt: Date?
    private let url: URL
    private var originalText = ""

    init(url: URL = VoiceTypeFiles.directory.appendingPathComponent("dictionary.txt")) { self.url = url }

    func load() {
        do {
            let text = try diskText()
            originalText = text
            document = DictionaryDocument(text: text)
            loaded = true
            error = nil
        } catch {
            loaded = false
            self.error = "無法讀取詞庫：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(id: UUID? = nil, correct: String, aliases: String?, mapping: Bool) -> Bool {
        let correct = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = DictionaryDocument.normalizedAliases(aliases ?? "")
        guard !correct.isEmpty, !correct.hasPrefix("#"),
              correct.rangeOfCharacter(from: CharacterSet(charactersIn: ":：\r\n")) == nil,
              !mapping || (!aliases.isEmpty && aliases.rangeOfCharacter(from: .newlines) == nil) else {
            error = "請填寫正確寫法；每筆限一行，不能以 # 開頭或包含冒號。對照行也需要填寫誤聽內容。"
            return false
        }
        var updated = document
        if let id, let index = updated.lines.firstIndex(where: { $0.id == id }) {
            updated.lines[index].correct = correct
            updated.lines[index].aliases = aliases
            updated.lines[index].edited = true
        } else {
            updated.lines.append(DictionaryLine(kind: mapping ? .mapping : .word,
                                                original: "", correct: correct, aliases: aliases, edited: true))
        }
        return persist(updated)
    }

    func delete(_ id: UUID) {
        var updated = document
        updated.lines.removeAll { $0.id == id }
        _ = persist(updated)
    }

    private func diskText() throws -> String {
        do { return try String(contentsOf: url, encoding: .utf8) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return ""
        }
    }

    private func persist(_ updated: DictionaryDocument) -> Bool {
        guard loaded else { error = "詞庫尚未載入，請先重新載入。"; return false }
        do {
            // 避免覆蓋使用者同時在文字編輯器裡做的修改。
            guard try diskText() == originalText else {
                error = "詞庫已被其他程式修改。請先重新載入，再套用這次修改。"
                return false
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.text.write(to: url, atomically: true, encoding: .utf8)
            document = updated
            originalText = updated.text
            savedAt = Date()
            error = nil
            return true
        } catch {
            self.error = "無法儲存詞庫：\(error.localizedDescription)"
            return false
        }
    }
}
