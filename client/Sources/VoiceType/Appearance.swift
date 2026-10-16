import AppKit
import SwiftUI

/// Haiyaa 的共用色票。介面與圖示產生器都從這裡取色。
enum Appearance {
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("Haiyaa.\(name)")) { appearance in
            rgb(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        }
    }

    static let yellow = rgb(0xF3C84B)
    static let amber = rgb(0xDFA832)
    static let ink = rgb(0x282828)
    static let iconTop = rgb(0x454545)
    static let iconBottom = rgb(0x292929)
    static let accentNS = adaptive("accent", light: 0x805B00, dark: 0xF3C84B)
    static let handsFreeNS = adaptive("handsFree", light: 0x805300, dark: 0xDFA832)
    static let accent = Color(nsColor: accentNS)
    static let handsFree = Color(nsColor: handsFreeNS)
    static let emphasis = Color(nsColor: yellow)
    static let onEmphasis = Color(nsColor: ink)
    static let canvas = Color(nsColor: adaptive("canvas", light: 0xEEEEEE, dark: 0x252525))
    static let sidebar = Color(nsColor: adaptive("sidebar", light: 0xE3E3E3, dark: 0x202020))
    static let card = Color(nsColor: adaptive("card", light: 0xFAFAFA, dark: 0x303030))
    static let inset = Color(nsColor: adaptive("inset", light: 0xE5E5E5, dark: 0x383838))
    static let hud = Color(nsColor: adaptive("hud", light: 0xE5E5E5, dark: 0x303030))
    static let border = Color(nsColor: adaptive("border", light: 0xD0D0D0, dark: 0x505050))
    static let error = Color(nsColor: adaptive("error", light: 0xB03920, dark: 0xFF9375))
    static let shadow = Color.black.opacity(0.18)
}

/// 黃底一定配深色文字，不受 macOS 系統重點色影響。
struct HaiyaaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(enabled ? Appearance.onEmphasis : Color.secondary)
            .background(enabled ? Appearance.emphasis : Appearance.inset,
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
