import AppKit

/// 편집기 왼쪽 줄: 줄 번호, 바뀐 줄 표시(초록=추가, 파랑=수정, 빨강=삭제), 제목 접기 단추(▾ ▸)
@MainActor
final class LineNumberRuler: NSRulerView {
    private weak var editor: EditorController?

    private let foldWidth: CGFloat = 14
    private let markerWidth: CGFloat = 6

    init(scrollView: NSScrollView, editor: EditorController) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor.textView
        ruleThickness = 40
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var numberFont: NSFont {
        let size = max(9, CGFloat(editor?.fontSize ?? Zoom.defaultSize) * 0.78)
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    func updateThickness() {
        guard let editor else { return }
        var width = foldWidth + markerWidth
        if editor.lineNumbers {
            let digits = max(2, String(editor.lineCount).count)
            let digitWidth = ("0" as NSString).size(withAttributes: [.font: numberFont]).width
            width += CGFloat(digits) * digitWidth + 6
        }
        if abs(ruleThickness - width) > 0.5 { ruleThickness = ceil(width) }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let lm = editor.textView.layoutManager, let tc = editor.textView.textContainer else { return }
        let tv = editor.textView
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let origin = tv.textContainerOrigin
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let caretLine = editor.caretLine
        let headingLevels = Dictionary(editor.headings.map { ($0.line, $0.level) }, uniquingKeysWith: { a, _ in a })

        func draw(line: Int, fragment: NSRect) {
            let y = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: tv).y
            let height = fragment.height

            if editor.lineNumbers {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: numberFont,
                    .foregroundColor: line == caretLine ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
                ]
                let label = "\(line + 1)" as NSString
                let size = label.size(withAttributes: attributes)
                let x = ruleThickness - markerWidth - 4 - size.width
                label.draw(at: NSPoint(x: x, y: y + (min(height, size.height * 1.6) - size.height) / 2), withAttributes: attributes)
            }

            if editor.showChanges {
                if let kind = editor.changeMarkers.lines[line] {
                    (kind == .added ? NSColor.systemGreen : NSColor.systemBlue).withAlphaComponent(0.8).setFill()
                    NSRect(x: ruleThickness - markerWidth + 1, y: y, width: 3, height: height).fill()
                }
                if editor.changeMarkers.deletions.contains(line) {
                    NSColor.systemRed.setFill()
                    let tri = NSBezierPath()
                    let x = ruleThickness - markerWidth
                    tri.move(to: NSPoint(x: x, y: y - 3))
                    tri.line(to: NSPoint(x: x + 5, y: y))
                    tri.line(to: NSPoint(x: x, y: y + 3))
                    tri.close()
                    tri.fill()
                }
            }

            if headingLevels[line] != nil {
                let folded = editor.isFolded(line: line)
                let size: CGFloat = 7
                let cx = foldWidth / 2 + 1
                let cy = y + min(height, numberFont.pointSize * 1.6) / 2
                let path = NSBezierPath()
                if folded {
                    path.move(to: NSPoint(x: cx - size / 3, y: cy - size / 2))
                    path.line(to: NSPoint(x: cx + size / 2, y: cy))
                    path.line(to: NSPoint(x: cx - size / 3, y: cy + size / 2))
                } else {
                    path.move(to: NSPoint(x: cx - size / 2, y: cy - size / 3))
                    path.line(to: NSPoint(x: cx + size / 2, y: cy - size / 3))
                    path.line(to: NSPoint(x: cx, y: cy + size / 2))
                }
                path.close()
                (folded ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
                path.fill()
            }
        }

        lm.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, _, _, fragmentGlyphs, _ in
            let index = lm.characterIndexForGlyph(at: fragmentGlyphs.location)
            let line = editor.line(at: index)
            if editor.lineStart(line) == index { draw(line: line, fragment: fragment) }
        }
        let extra = lm.extraLineFragmentRect
        if extra.height > 0 { draw(line: editor.lineCount - 1, fragment: extra) }
    }

    /// ▾ 를 누르면 접고, 줄 번호를 누르면 그 줄을 선택합니다.
    override func mouseDown(with event: NSEvent) {
        guard let editor, let lm = editor.textView.layoutManager, let tc = editor.textView.textContainer else { return }
        let tv = editor.textView
        let point = tv.convert(convert(event.locationInWindow, from: nil), from: self)
        let local = NSPoint(x: 0, y: point.y - tv.textContainerOrigin.y)
        let index: Int
        if lm.numberOfGlyphs == 0 || local.y >= lm.extraLineFragmentRect.minY && lm.extraLineFragmentRect.height > 0 {
            index = editor.length
        } else {
            index = lm.characterIndexForGlyph(at: lm.glyphIndex(for: local, in: tc))
        }
        let line = editor.line(at: index)
        if editor.headings.contains(where: { $0.line == line }), convert(event.locationInWindow, from: nil).x < foldWidth + 4 {
            editor.toggleFold(line: line)
        } else {
            let range = (tv.string as NSString).lineRange(for: NSRange(location: editor.lineStart(line), length: 0))
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(range)
        }
        needsDisplay = true
    }
}
