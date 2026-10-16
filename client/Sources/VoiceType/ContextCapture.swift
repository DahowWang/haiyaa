import Cocoa
import ApplicationServices

/// 用輔助使用（Accessibility）API 抓講話當下的畫面資訊：App、視窗標題、網址、游標前後文字。
enum ContextCapture {
    static func capture() -> [String: String] {
        var ctx: [String: String] = [:]
        guard let app = NSWorkspace.shared.frontmostApplication else { return ctx }
        ctx["app"] = app.localizedName ?? ""
        ctx["bundle_id"] = app.bundleIdentifier ?? ""

        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.3)
        // Electron App（Slack、Notion、VS Code…）要先打開這個才會吐出畫面內容
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        if let win: AXUIElement = attr(appEl, kAXFocusedWindowAttribute),
           let title: String = attr(win, kAXTitleAttribute), !title.isEmpty {
            ctx["window_title"] = title
        }

        guard let focused: AXUIElement = attr(appEl, kAXFocusedUIElementAttribute) else { return ctx }

        if let value: String = attr(focused, kAXValueAttribute), !value.isEmpty {
            let ns = value as NSString
            var loc = ns.length
            if let rangeVal: AXValue = attr(focused, kAXSelectedTextRangeAttribute) {
                var r = CFRange()
                if AXValueGetValue(rangeVal, .cfRange, &r) { loc = min(max(r.location, 0), ns.length) }
            }
            let start = max(0, loc - 1500)
            ctx["before"] = ns.substring(with: NSRange(location: start, length: loc - start))
            ctx["after"] = ns.substring(with: NSRange(location: loc, length: min(500, ns.length - loc)))
        }
        if let sel: String = attr(focused, kAXSelectedTextAttribute), !sel.isEmpty {
            ctx["selected"] = sel
        }

        // 瀏覽器：往上找網頁區塊的 AXURL
        var el: AXUIElement? = focused
        for _ in 0..<40 {
            guard let cur = el else { break }
            if let url: URL = attr(cur, "AXURL") {
                ctx["url"] = url.absoluteString
                break
            }
            el = attr(cur, kAXParentAttribute)
        }
        return ctx
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return nil }
        if T.self == AXUIElement.self || T.self == AXValue.self { return (v as! T) }
        return v as? T
    }
}
