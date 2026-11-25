import AppKit

extension NSAttributedString.Key {
    /// 접힌 부분 표시. 저장되는 글에는 영향이 없고 화면에서만 숨깁니다.
    static let mdyFolded = NSAttributedString.Key("MdyFolded")
}

/// 제목 접기: 제목 아래 내용(다음 같은·상위 제목 전까지)을 화면에서 숨깁니다.
extension EditorController: @preconcurrency NSLayoutManagerDelegate {
    /// 제목 줄 다음부터 다음 같은 수준 제목 바로 앞까지
    func foldRange(heading line: Int) -> NSRange? {
        guard let item = headings.first(where: { $0.line == line }) else { return nil }
        let next = headings.first(where: { $0.line > line && $0.level <= item.level })
        let start = NSMaxRange(characterRange(lines: line, line))
        let end = next.map { lineStart($0.line) - 1 } ?? length
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    func isFolded(line: Int) -> Bool {
        guard hasFolds, let range = foldRange(heading: line), let storage = textView.textStorage,
              range.location < storage.length else { return false }
        return storage.attribute(.mdyFolded, at: range.location, effectiveRange: nil) != nil
    }

    func toggleFold(line: Int) {
        guard let range = foldRange(heading: line) else { NSSound.beep(); return }
        if isFolded(line: line) { unfold(range) } else { fold(range) }
    }

    private func fold(_ range: NSRange) {
        guard let storage = textView.textStorage else { return }
        storage.addAttribute(.mdyFolded, value: true, range: range)
        hasFolds = true
        invalidate(range)
        // 커서가 접힌 곳 안에 있으면 제목 끝으로
        let sel = textView.selectedRange()
        if NSLocationInRange(sel.location, range) || (sel.location == NSMaxRange(range) && sel.location > range.location) {
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
        }
    }

    private func unfold(_ range: NSRange) {
        guard let storage = textView.textStorage else { return }
        storage.removeAttribute(.mdyFolded, range: range)
        invalidate(range)
        var any = false
        storage.enumerateAttribute(.mdyFolded, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if value != nil { any = true; stop.pointee = true }
        }
        hasFolds = any
    }

    private func invalidate(_ range: NSRange) {
        guard let lm = textView.layoutManager else { return }
        lm.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        textView.needsDisplay = true
        ruler?.needsDisplay = true
    }

    /// 커서·검색·위치 표시가 접힌 곳으로 들어가면 그 부분을 펼칩니다.
    func revealFolded(at location: Int) {
        guard hasFolds, let storage = textView.textStorage, storage.length > 0 else { return }
        for index in [location, location - 1] where index >= 0 && index < storage.length {
            var effective = NSRange()
            if storage.attribute(.mdyFolded, at: index, effectiveRange: &effective) != nil,
               index == location || NSMaxRange(effective) > location {
                unfold(effective)
                return
            }
        }
    }

    /// 커서가 있는 곳의 제목
    private var currentHeadingLine: Int? {
        let caret = caretLine
        return headings.last(where: { $0.line <= caret })?.line
    }

    func foldCurrent() {
        guard let line = currentHeadingLine, let range = foldRange(heading: line), !isFolded(line: line) else { NSSound.beep(); return }
        fold(range)
    }

    func unfoldCurrent() {
        guard let line = currentHeadingLine, let range = foldRange(heading: line), isFolded(line: line) else { NSSound.beep(); return }
        unfold(range)
    }

    func foldAll() {
        for item in headings.reversed() {
            if let range = foldRange(heading: item.line) { fold(range) }
        }
    }

    func unfoldAll() {
        guard let storage = textView.textStorage else { return }
        unfold(NSRange(location: 0, length: storage.length))
    }

    // MARK: NSLayoutManagerDelegate — 접힌 글자는 그리지 않음

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard hasFolds, let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var newProps = [NSLayoutManager.GlyphProperty]()
        newProps.reserveCapacity(count)
        var changed = false
        for i in 0..<count {
            let index = charIndexes[i]
            if index < storage.length, storage.attribute(.mdyFolded, at: index, effectiveRange: nil) != nil {
                newProps.append(.null)
                changed = true
            } else {
                newProps.append(props[i])
            }
        }
        guard changed else { return 0 }
        newProps.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
        }
        return count
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if hasFolds, let storage = layoutManager.textStorage, charIndex < storage.length,
           storage.attribute(.mdyFolded, at: charIndex, effectiveRange: nil) != nil {
            return .zeroAdvancement
        }
        return action
    }
}
