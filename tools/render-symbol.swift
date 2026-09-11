// SF Symbol 을 PNG 로 렌더링한다.
// 설치 화면(welcome/conclusion)은 HTML 이라 심볼을 직접 쓸 수 없어서,
// 앱에서 쓰는 것과 똑같은 심볼을 이미지로 구워 넣기 위한 빌드 도구.
//
// 사용법: render-symbol <심볼이름> <포인트크기> <색상HEX> <출력경로>

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 5,
      let points = Double(args[2]) else {
    FileHandle.standardError.write("사용법: render-symbol <symbol> <points> <RRGGBB> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let symbol = args[1]
let hex = args[3]
let outPath = args[4]

func color(fromHex h: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                   green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255,
                   alpha: 1)
}

let cfg = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
        .withSymbolConfiguration(cfg) else {
    FileHandle.standardError.write("심볼을 찾을 수 없음: \(symbol)\n".data(using: .utf8)!)
    exit(1)
}

// 심볼은 템플릿(알파 마스크)이므로 sourceAtop 으로 색을 채운다.
let size = base.size
let canvas = NSImage(size: size)
canvas.lockFocus()
base.draw(in: NSRect(origin: .zero, size: size))
color(fromHex: hex).set()
NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
canvas.unlockFocus()

// lockFocus 는 화면 배율을 따르므로, 픽셀 크기를 고정하려면
// bitmap rep 를 직접 만들어 다시 그린다.
let scale = 2   // Retina 용 2배
let px = NSBitmapImageRep(bitmapDataPlanes: nil,
                          pixelsWide: Int(size.width) * scale,
                          pixelsHigh: Int(size.height) * scale,
                          bitsPerSample: 8, samplesPerPixel: 4,
                          hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB,
                          bytesPerRow: 0, bitsPerPixel: 0)!
px.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: px)
canvas.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

guard let png = px.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 변환 실패\n".data(using: .utf8)!)
    exit(1)
}
do { try png.write(to: URL(fileURLWithPath: outPath)) }
catch {
    FileHandle.standardError.write("쓰기 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
