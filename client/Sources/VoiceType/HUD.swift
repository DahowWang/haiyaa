import Cocoa
import Combine
import SwiftUI

private final class HUDModel: ObservableObject {
    enum Phase: Equatable { case preparing, recording, processing, done, error }
    @Published var phase: Phase = .preparing
    @Published var handsFree = false
    @Published var seconds = 0
    @Published var bars = Array(repeating: CGFloat(4), count: 16)
    @Published var pulse: CGFloat = 0.5
    @Published var message = ""
}

/// 不啟用 App、不接收滑鼠事件，讓游標留在原本的輸入位置。
final class HUD {
    private let panel: NSPanel
    private let model = HUDModel()
    private var timer: Timer?
    private var dismissal: DispatchWorkItem?
    private var generation = 0
    private var startedAt = Date()
    private var tick = 0.0
    private var ready = false
    private var recording = false
    private var smoothedLevel = 0.0
    var levelProvider: (() -> Float)?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: FlowBar(model: model))
    }

    func markReady() {
        guard recording, !ready else { return }
        ready = true
        startedAt = Date()
        withAnimation(.easeInOut(duration: 0.2)) { model.phase = .recording }
    }

    func showRecording(handsFree: Bool) {
        if !recording {
            startedAt = Date()
            ready = false
            smoothedLevel = 0
            model.seconds = 0
            model.bars = Array(repeating: 4, count: 16)
        }
        recording = true
        withAnimation(.easeInOut(duration: 0.2)) {
            model.handsFree = handsFree
            model.phase = ready ? .recording : .preparing
        }
        startTimer()
        present()
    }

    func showProcessing() {
        recording = false
        withAnimation(.easeInOut(duration: 0.2)) { model.phase = .processing }
        startTimer()
        present()
    }

    func showDone(text: String) {
        showMessage(String(text.prefix(18)) + (text.count > 18 ? "…" : ""), phase: .done, duration: 1.2)
    }

    func showError(_ msg: String) {
        showMessage(msg, phase: .error, duration: 3)
    }

    func hide() {
        stopTimer()
        recording = false
        dismissal?.cancel()
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }

    private func showMessage(_ text: String, phase: HUDModel.Phase, duration: Double) {
        stopTimer()
        recording = false
        withAnimation(.easeInOut(duration: 0.2)) {
            model.message = text
            model.phase = phase
        }
        present()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func animate() {
        tick += 1.0 / 30
        model.pulse = 0.45 + 0.35 * CGFloat(sin(tick * 3))
        if model.phase == .recording {
            model.seconds = Int(Date().timeIntervalSince(startedAt))
            let sample = Double(levelProvider?() ?? 0)
            let level = sample.isFinite ? min(1, max(0, sample)) : 0
            smoothedLevel += (level - smoothedLevel) * (level > smoothedLevel ? 0.45 : 0.16)
        }
        let processing = model.phase == .processing
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.68)) {
            model.bars = (0..<16).map { index in
                let wave = (sin(tick * (processing ? 4 : 11) - Double(index) * 0.65) + 1) / 2
                let envelope = 0.45 + 0.55 * sin(Double(index + 1) / 17 * .pi)
                return CGFloat(4 + (processing ? 16 * wave : 26 * smoothedLevel * (0.35 + wave * 0.65)) * envelope)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func present() {
        dismissal?.cancel()
        generation += 1
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 28))
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }
}

private struct FlowBar: View {
    @ObservedObject var model: HUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tint: Color { model.handsFree ? Appearance.handsFree : Appearance.accent }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                switch model.phase {
                case .preparing:
                    Circle().fill(Appearance.accent.opacity(reduceMotion ? 0.6 : model.pulse))
                        .frame(width: 7, height: 7)
                    Text("等麥克風準備好…").foregroundStyle(.secondary)
                case .recording, .processing:
                    waveform
                    if model.phase == .recording {
                        Text("我在聽").foregroundStyle(.primary)
                        Text(String(format: "%d:%02d", model.seconds / 60, model.seconds % 60))
                            .monospacedDigit().foregroundStyle(tint)
                    } else {
                        Text("正在轉成文字…").foregroundStyle(.secondary)
                    }
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Appearance.accent)
                    Text(model.message).lineLimit(1)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Appearance.error)
                    Text(model.message).font(.system(size: 12)).lineLimit(2)
                }
            }
            .font(.system(size: 13, weight: .medium))
            if model.phase == .recording {
                HStack(spacing: 5) {
                    Image(systemName: model.handsFree ? "lock.open.fill" : "hand.point.up.left.fill")
                        .foregroundStyle(tint)
                    Text(model.handsFree ? "免持・再點左 Option 送出・Esc 取消" : "按住說話・放開送出・Esc 取消")
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Appearance.hud, in: Capsule())
        .overlay(Capsule().strokeBorder(Appearance.border, lineWidth: 0.5))
        .shadow(color: Appearance.shadow, radius: 8, y: 3)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                Capsule().fill(model.phase == .processing ? Appearance.accent.opacity(0.75) : tint)
                    .frame(width: 3, height: reduceMotion ? 9 : model.bars[index])
            }
        }
        .frame(height: 30)
        .accessibilityLabel(model.phase == .processing ? "辨識中" : "錄音中")
    }
}
