// 在 client/ 編譯並執行（與 App 共用 Appearance.swift 色票）：
// swiftc Sources/VoiceType/Appearance.swift scripts/GenerateAppIcon.swift -o /tmp/haiyaa-icon
// /tmp/haiyaa-icon
import AppKit

@main
struct GenerateAppIcon {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/VoiceType/Appearance.swift").path) else {
            throw NSError(domain: "HaiyaaIcon", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "請在 client/ 執行圖示產生器。"])
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill(using: .copy)

        // 四周各留約 10%，採 macOS 圓角方塊輪廓。
        let tile = NSBezierPath(roundedRect: NSRect(x: 102, y: 102, width: 820, height: 820),
                                xRadius: 184, yRadius: 184)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = Appearance.ink.withAlphaComponent(0.23)
        shadow.shadowBlurRadius = 15
        shadow.shadowOffset = NSSize(width: 0, height: -7)
        shadow.set()
        Appearance.iconBottom.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: Appearance.iconBottom, ending: Appearance.iconTop)!.draw(in: tile, angle: 90)
        Appearance.iconTop.withAlphaComponent(0.8).setStroke()
        tile.lineWidth = 2
        tile.stroke()

        // 一個正在說話的泡泡；不使用人物、品牌字體或第三方標誌。
        let bubble = NSBezierPath(roundedRect: NSRect(x: 248, y: 350, width: 528, height: 368),
                                  xRadius: 136, yRadius: 136)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 344, y: 390))
        tail.line(to: NSPoint(x: 332, y: 280))
        tail.curve(to: NSPoint(x: 468, y: 376),
                   controlPoint1: NSPoint(x: 386, y: 289), controlPoint2: NSPoint(x: 433, y: 331))
        tail.close()
        Appearance.yellow.setFill()
        tail.fill()
        bubble.fill()

        // 圓頭聲波保留語音辨識意象，縮到 Dock 尺寸仍能辨認。
        let heights: [CGFloat] = [78, 142, 210, 158, 94]
        Appearance.ink.setFill()
        for (index, height) in heights.enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 368 + CGFloat(index) * 62,
                                            y: 534 - height / 2, width: 40, height: height),
                         xRadius: 20, yRadius: 20).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let png = resources.appendingPathComponent("AppIcon-1024.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: png, options: .atomic)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("haiyaa-icon-\(UUID().uuidString)")
        let iconset = temporary.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = String(size * scale)
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try run("/usr/bin/sips", ["-z", pixels, pixels, png.path, "--out", iconset.appendingPathComponent(name).path])
            }
        }
        let icns = temporary.appendingPathComponent("AppIcon.icns")
        do {
            try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path])
        } catch {
            // 部分受限環境可解開 icns，卻無法呼叫系統圖示編碼服務。
            // 封裝同一組 sips 圖像為標準 icns 區塊，仍保留全部 10 種尺寸。
            print("iconutil 封裝失敗，改用圖示區塊備援：\(error.localizedDescription)")
            try iconContainer(iconset: iconset).write(to: icns, options: .atomic)
        }
        try Data(contentsOf: icns).write(to: resources.appendingPathComponent("AppIcon.icns"), options: .atomic)
        print("已產生 Resources/AppIcon-1024.png 與 Resources/AppIcon.icns")
    }

    private static func iconContainer(iconset: URL) throws -> Data {
        let variants = [
            ("ic11", "16x16@2x"),
            ("ic12", "32x32@2x"),
            ("ic07", "128x128"), ("ic13", "128x128@2x"),
            ("ic08", "256x256"), ("ic14", "256x256@2x"),
            ("ic09", "512x512"), ("ic10", "512x512@2x")
        ]
        func length(_ value: Int) -> Data {
            var bigEndian = UInt32(value).bigEndian
            return withUnsafeBytes(of: &bigEndian) { Data($0) }
        }
        var chunks = Data()
        func append(_ type: String, _ payload: Data) {
            chunks.append(Data(type.utf8))
            chunks.append(length(payload.count + 8))
            chunks.append(payload)
        }
        // 16/32 的標準倍率使用 RGB + alpha mask，避免舊解碼器誤讀 PNG。
        // 格式參考：https://github.com/relikd/icns-analysis
        for (size, type, mask) in [(16, "is32", "s8mk"), (32, "il32", "l8mk")] {
            let data = try Data(contentsOf: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
            let bitmap = NSBitmapImageRep(data: data)!
            var channels = [[UInt8]](repeating: [], count: 4)
            for y in 0..<size {
                for x in 0..<size {
                    // 舊式 RGB 區塊以 Generic RGB 解碼；先轉色域，避免小圖偏亮。
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.genericRGB)!
                    for (index, component) in [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].enumerated() {
                        channels[index].append(UInt8((min(1, max(0, component)) * 255).rounded()))
                    }
                }
            }
            var rgb = Data()
            for channel in channels.prefix(3) {
                // RLE 的 literal 區塊：控制位元組 0...127 代表後續 1...128 bytes。
                for start in stride(from: 0, to: channel.count, by: 128) {
                    let end = min(start + 128, channel.count)
                    rgb.append(UInt8(end - start - 1))
                    rgb.append(contentsOf: channel[start..<end])
                }
            }
            append(type, rgb)
            append(mask, Data(channels[3]))
        }
        for (type, size) in variants {
            let png = try Data(contentsOf: iconset.appendingPathComponent("icon_\(size).png"))
            append(type, png)
        }
        var result = Data("icns".utf8)
        result.append(length(chunks.count + 8))
        result.append(chunks)
        return result
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "HaiyaaIcon", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(executable) 執行失敗"])
        }
    }
}
