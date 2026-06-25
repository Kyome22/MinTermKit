import Testing
import AppKit
import CoreGraphics
@testable import MinTermKit

@MainActor
private func nonBlankPixelCount(terminal: Terminal, metrics: FontMetrics, width: Int, height: Int) -> Int {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let count = data.withUnsafeMutableBytes { raw -> Int in
        guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        CanvasRenderer(metrics: metrics).render(into: ctx, size: CGSize(width: width, height: height),
                                                terminal: terminal, selection: nil)
        var bright = 0
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            if raw[index] > 40 || raw[index + 1] > 40 || raw[index + 2] > 40 { bright += 1 }
        }
        return bright
    }
    return count
}

@MainActor
@Test func rendererKeepsPixelsAfterWidthShrink() {
    let terminal = Terminal(cols: 40, rows: 10)
    terminal.feed(text: "HELLO WORLD")
    let metrics = FontMetrics(font: .monospacedSystemFont(ofSize: 13, weight: .regular))

    let before = nonBlankPixelCount(terminal: terminal, metrics: metrics, width: 320, height: 160)
    terminal.resize(cols: 12, rows: 10)
    let after = nonBlankPixelCount(terminal: terminal, metrics: metrics, width: 100, height: 160)

    print("=== pixels before=\(before) after=\(after) ===")
    #expect(before > 0)
    #expect(after > 0)
}
