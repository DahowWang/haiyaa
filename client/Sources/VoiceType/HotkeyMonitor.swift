import Cocoa

/// 左 Option 的兩種用法：
/// - 按住說話：按下開始錄、放開送出；按住期間按了其他鍵就當成 Option 組合鍵，取消這次錄音。
/// - 免持：點一下開始錄（可以放手），再點一下送出，按 Esc 取消。
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHandsFree: (() -> Void)?
    var log: ((String) -> Void)?

    private let keyCode: Int64 = 58  // 左 Option
    private let escKeyCode: Int64 = 53
    private let tapMax: TimeInterval = 1.0  // 按下到放開短於這個算「點一下」

    private var tap: CFMachPort?
    private var isDown = false
    private var cancelled = false
    private var pressedAt = Date.distantPast
    private var handsFree = false
    private var swallowNextUp = false

    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                me.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            if handsFree {
                if event.getIntegerValueField(.keyboardEventKeycode) == escKeyCode {
                    log?("Esc：取消免持錄音")
                    handsFree = false
                    onCancel?()
                }
            } else if isDown && !cancelled {
                log?("按住 Option 時按了其他鍵（keyCode \(event.getIntegerValueField(.keyboardEventKeycode))），取消")
                cancelled = true
                onCancel?()
            }
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let optionDown = flags.contains(.maskAlternate)
            if code == keyCode {
                if optionDown && !isDown {
                    isDown = true
                    if handsFree {
                        // 免持中再點一下 Option：送出
                        handsFree = false
                        swallowNextUp = true
                        onRelease?()
                        return
                    }
                    // 同時按著 Cmd／Ctrl／Shift 時不觸發，留給一般快捷鍵
                    guard flags.intersection([.maskCommand, .maskControl, .maskShift]).isEmpty else {
                        cancelled = true
                        return
                    }
                    cancelled = false
                    pressedAt = Date()
                    onPress?()
                } else if !optionDown && isDown {
                    isDown = false
                    if swallowNextUp { swallowNextUp = false; return }
                    if cancelled { return }
                    let now = Date()
                    let held = now.timeIntervalSince(pressedAt)
                    log?(String(format: "放開 Option：按了 %.2f 秒 → %@", held, held >= tapMax ? "按住說話，送出" : "點一下，進入免持"))
                    if held >= tapMax {
                        onRelease?()
                    } else {
                        // 點一下：錄音繼續，進入免持，等下一次點擊送出
                        handsFree = true
                        onHandsFree?()
                    }
                }
            } else if isDown && !cancelled && !handsFree {
                // 按住 Option 時又按了其他修飾鍵
                log?("按住 Option 時按了其他修飾鍵（keyCode \(code)），取消")
                cancelled = true
                onCancel?()
            }
        default:
            break
        }
    }
}
