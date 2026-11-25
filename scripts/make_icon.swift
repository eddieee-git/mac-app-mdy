// 앱 아이콘(.iconset PNG들)을 그려요. 사용: swift make_icon.swift <출력.iconset> [큰 PNG 경로]
// 그림: 보라색 바탕 위 종이 한 장. 왼쪽 반은 원본(# 과 코드 줄), 오른쪽 반은 다듬어진 미리보기(제목·글·그림).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = CGFloat(px) / 1024          // 1024 기준 좌표를 쓰고 크기만 맞춰요
    ctx.scaleBy(x: k, y: k)

    // 바탕: macOS 아이콘 격자(1024 캔버스에 824 둥근 사각형)
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x6A4BE0).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xA07CFF), color(0x7552F0), color(0x5536C8)],
               atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: tilePath, angle: -90)

    // 종이
    let page = NSRect(x: 222, y: 205, width: 580, height: 614)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 44, yRadius: 44)
    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = color(0x2A1670, 0.45)
    pageShadow.shadowBlurRadius = 30
    pageShadow.shadowOffset = NSSize(width: 0, height: -14)
    pageShadow.set()
    NSColor.white.setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 왼쪽 반: 원본은 살짝 회색 종이
    NSGraphicsContext.saveGraphicsState()
    pagePath.addClip()
    color(0xF1EEFB).setFill()
    NSRect(x: page.minX, y: page.minY, width: page.width / 2, height: page.height).fill()
    NSGraphicsContext.restoreGraphicsState()

    // 가운데 구분선과 손잡이
    let mid = page.midX
    color(0xD9D3F2).setFill()
    NSRect(x: mid - 3, y: page.minY, width: 6, height: page.height).fill()
    color(0x8C7AD9).setFill()
    NSBezierPath(roundedRect: NSRect(x: mid - 9, y: page.midY - 46, width: 18, height: 92), xRadius: 9, yRadius: 9).fill()

    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
    }

    // 왼쪽: # 제목 줄과 코드처럼 들쭉날쭉한 줄들
    let leftX = page.minX + 44
    let hash = NSAttributedString(string: "#", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 92, weight: .heavy),
        .foregroundColor: color(0x6A4BE0),
    ])
    hash.draw(at: NSPoint(x: leftX - 4, y: page.maxY - 146))
    bar(leftX + 66, page.maxY - 104, 120, 26, color(0xB9AEE6))
    let sourceLines: [(CGFloat, CGFloat, UInt32)] = [
        (0, 196, 0xC9C1EA), (0, 150, 0xC9C1EA), (0, 182, 0xC9C1EA),
        (28, 126, 0xE2A85C), (28, 158, 0xC9C1EA), (0, 104, 0xC9C1EA),
    ]
    var y = page.maxY - 196
    for (indent, width, hex) in sourceLines {
        bar(leftX + indent, y, width, 20, color(hex))
        y -= 58
    }

    // 오른쪽: 굵은 제목, 글 줄, 그림 한 장
    let rightX = mid + 40
    bar(rightX, page.maxY - 104, 196, 40, color(0x3B2A86))
    for (i, width) in [212, 176, 200].enumerated() {
        bar(rightX, page.maxY - 168 - CGFloat(i) * 46, CGFloat(width), 18, color(0xCFCBE0))
    }
    let photo = NSRect(x: rightX, y: page.minY + 96, width: 214, height: 168)
    let photoPath = NSBezierPath(roundedRect: photo, xRadius: 22, yRadius: 22)
    color(0xE6DEFF).setFill()
    photoPath.fill()
    NSGraphicsContext.saveGraphicsState()
    photoPath.addClip()
    color(0xFFC857).setFill()
    NSBezierPath(ovalIn: NSRect(x: photo.maxX - 74, y: photo.maxY - 70, width: 44, height: 44)).fill()
    let hills = NSBezierPath()
    hills.move(to: NSPoint(x: photo.minX, y: photo.minY))
    hills.line(to: NSPoint(x: photo.minX, y: photo.minY + 54))
    hills.line(to: NSPoint(x: photo.minX + 70, y: photo.minY + 112))
    hills.line(to: NSPoint(x: photo.minX + 124, y: photo.minY + 62))
    hills.line(to: NSPoint(x: photo.minX + 160, y: photo.minY + 90))
    hills.line(to: NSPoint(x: photo.maxX, y: photo.minY + 40))
    hills.line(to: NSPoint(x: photo.maxX, y: photo.minY))
    hills.close()
    color(0x7B5CF0).setFill()
    hills.fill()
    NSGraphicsContext.restoreGraphicsState()
    bar(rightX, page.minY + 50, 150, 18, color(0xCFCBE0))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    try draw(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
