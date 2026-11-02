import AppKit
import SwiftUI

/// 放開滑鼠後才回報選字，避免拖曳選取到一半就打開修正視窗。
struct HistorySelectableText: NSViewRepresentable {
    let text: String
    let onSelection: (String) -> Void

    func makeNSView(context: Context) -> SelectionTextView {
        let view = SelectionTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: SelectionTextView, context: Context) {
        if view.string != text { view.string = text }
        view.onSelection = onSelection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectionTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        let width = max(1, proposal.width ?? 400)
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(22, ceil(layout.usedRect(for: container).height)))
    }
}

final class SelectionTextView: NSTextView {
    var onSelection: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        reportSelection()
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if (event.keyCode == 56 || event.keyCode == 60) && !event.modifierFlags.contains(.shift) { reportSelection() }
    }

    private func reportSelection() {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
        let selected = (string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        let callback = onSelection
        DispatchQueue.main.async { callback?(selected) }
    }
}
