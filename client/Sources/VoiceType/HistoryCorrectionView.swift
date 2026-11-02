import SwiftUI

struct HistoryCorrectionView: View {
    let entry: HistoryEntry
    @ObservedObject var dictionary: DictionaryStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var misheard: String
    @State private var correct = ""
    @FocusState private var focused: Field?
    private enum Field { case misheard, correct }

    init(entry: HistoryEntry, dictionary: DictionaryStore, misheard: String = "", onSaved: @escaping () -> Void) {
        self.entry = entry
        self.dictionary = dictionary
        self.onSaved = onSaved
        _misheard = State(initialValue: misheard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Appearance.onEmphasis)
                        .frame(width: 48, height: 48)
                        .background(Appearance.emphasis, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("修正誤聽").font(.system(size: 22, weight: .bold))
                        Text("記住這個詞的正確寫法。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(alignment: .center, spacing: 12) {
                    wordField("聽錯的詞", placeholder: "例如：海呀", text: $misheard, field: .misheard)
                    Image(systemName: "arrow.right").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.tertiary).padding(.top, 22)
                    wordField("正確寫法", placeholder: "例如：Haiyaa", text: $correct, field: .correct)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("來自這筆紀錄", systemImage: "quote.opening")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(entry.app).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    ScrollView {
                        Text(entry.final.isEmpty ? entry.rawA : entry.final)
                            .font(.system(size: 14)).lineSpacing(5)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 85)
                }
                .padding(16).background(Appearance.inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))

                if let error = dictionary.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(Appearance.error)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("重新載入詞庫") { dictionary.load() }
                    }
                }
            }
            .padding(28)
            Divider().overlay(Appearance.border.opacity(0.4))
            HStack(spacing: 12) {
                Label("下次辨識自動套用", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction).buttonStyle(.plain)
                    .foregroundStyle(.secondary).padding(.horizontal, 10)
                Button(action: save) { Label("加入詞庫", systemImage: "plus") }
                    .keyboardShortcut(.defaultAction).buttonStyle(HaiyaaPrimaryButtonStyle())
                    .disabled(!dictionary.loaded || misheard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              correct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
        }
        .frame(width: 540)
        .background(Appearance.card).tint(Appearance.accent)
        .onAppear { focused = misheard.isEmpty ? .misheard : .correct }
    }

    private func wordField(_ title: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 17, weight: field == .correct ? .medium : .regular))
                .focused($focused, equals: field).accessibilityLabel(title)
                .padding(.horizontal, 14).padding(.vertical, 14)
                .background(Appearance.canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused == field ? Appearance.accent.opacity(0.6) : Appearance.border.opacity(0.7),
                                  lineWidth: focused == field ? 1.5 : 0.5))
                .onSubmit { if field == .misheard { focused = .correct } else { save() } }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        if dictionary.learn(correct: correct, misheard: misheard) {
            onSaved()
            dismiss()
        }
    }
}
