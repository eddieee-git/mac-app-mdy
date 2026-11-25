import AppKit
import UniformTypeIdentifiers

/// 편집기와 미리보기가 주고받는 스크롤 위치. line 은 원본 줄 번호(0부터, 소수점은 줄 안의 비율).
struct ScrollPosition {
    enum Edge: String { case none = "", top, bottom }
    var line: Double
    var edge: Edge
}

/// 붙여넣기·끌어놓기를 가로채고, 괄호·기호 짝 맞추기를 하는 텍스트 뷰
final class MdyTextView: NSTextView {
    /// 붙여넣기를 직접 처리했으면 true (그러면 기본 동작을 하지 않음)
    var pasteHandler: ((NSPasteboard, Int?) -> Bool)?
    var autoPair = true

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "`": "`", "\"": "\""]
    /// 선택한 글자를 감쌀 때만 쓰는 기호 (그냥 칠 때는 짝을 넣지 않음)
    private static let wrapOnly: [String: String] = ["*": "*", "_": "_", "~": "~", "=": "=", "<": ">"]
    private static let closers: Set<String> = [")", "]", "}", "`", "\""]

    override func paste(_ sender: Any?) {
        if pasteHandler?(.general, nil) == true { return }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        if pasteHandler?(sender.draggingPasteboard, index) == true { return true }
        return super.performDragOperation(sender)
    }

    private func character(at index: Int) -> String? {
        let ns = string as NSString
        guard index >= 0, index < ns.length else { return nil }
        return ns.substring(with: NSRange(location: index, length: 1))
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // 직접 친 글자 한 개일 때만 (프로그램이 바꾸는 내용·한글 조합 중에는 손대지 않음)
        guard autoPair, replacementRange.location == NSNotFound, !hasMarkedText(),
              let typed = string as? String, typed.count == 1 else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let sel = selectedRange()
        let next = character(at: sel.location)
        let prev = character(at: sel.location - 1)

        // 이미 있는 닫는 기호는 건너뛰기
        if sel.length == 0, Self.closers.contains(typed), next == typed {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }
        // 선택한 글자 감싸기
        if sel.length > 0, let close = Self.pairs[typed] ?? Self.wrapOnly[typed] {
            let inner = (self.string as NSString).substring(with: sel)
            super.insertText(typed + inner + close, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
            return
        }
        // 짝 넣기: 뒤가 비어 있을 때만
        if sel.length == 0, let close = Self.pairs[typed] {
            let nextIsFree = next == nil || next!.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || Self.closers.contains(next!)
            let prevIsWordy = prev.map { $0.rangeOfCharacter(from: .alphanumerics) != nil } ?? false
            let fenceInProgress = typed == "`" && character(at: sel.location - 2) == "`" && prev == "`"
            let quoteAfterWord = typed == "\"" && prevIsWordy
            if nextIsFree, !fenceInProgress, !quoteAfterWord {
                super.insertText(typed + close, replacementRange: sel)
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if autoPair, sel.length == 0, let prev = character(at: sel.location - 1), let next = character(at: sel.location),
           Self.pairs[prev] == next {
            insertText("", replacementRange: NSRange(location: sel.location - 1, length: 2))
            return
        }
        super.deleteBackward(sender)
    }
}

/// 창마다 하나의 NSTextView 를 유지해서, 보기 모드를 바꿔도
/// 커서 위치·선택·실행 취소 기록이 사라지지 않게 합니다.
@MainActor
final class EditorController: NSObject, ObservableObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    let scrollView: NSScrollView
    let textView: MdyTextView
    private(set) var ruler: LineNumberRuler!

    var onChange: ((String) -> Void)?
    /// 사용자가 편집기에서 커서·선택을 바꿨을 때 (시작 줄, 끝 줄, 선택한 글자)
    var onSelectionChange: ((Int, Int, String) -> Void)?
    var onCaretChange: ((CaretInfo) -> Void)?
    var onScroll: ((ScrollPosition) -> Void)?
    /// 서식 있는 붙여넣기(HTML)를 마크다운으로 바꿔 주는 곳 (미리보기 웹뷰의 변환기)
    var richPasteConverter: ((String, @escaping (String?) -> Void) -> Void)?

    /// 붙여넣은 이미지를 저장할 위치를 정하려고 문서 경로를 압니다.
    var documentURL: URL?
    var imageFolder = "images"
    var autoList = true
    var convertRichPaste = true
    var autoPair: Bool {
        get { textView.autoPair }
        set { textView.autoPair = newValue }
    }
    var coloring = true {
        didSet { if coloring != oldValue { recolor() } }
    }
    var focusMode = false {
        didSet { if focusMode != oldValue { recolor() } }
    }
    var typewriter = false {
        didSet { if typewriter != oldValue { updateInsets(); centerCaret() } }
    }
    var spellCheck: Bool {
        get { textView.isContinuousSpellCheckingEnabled }
        set { if textView.isContinuousSpellCheckingEnabled != newValue { textView.isContinuousSpellCheckingEnabled = newValue } }
    }
    var lineNumbers = false {
        didSet { if lineNumbers != oldValue { updateRuler() } }
    }
    var showChanges = false {
        didSet { if showChanges != oldValue { updateRuler() } }
    }
    var changeMarkers = ChangeMarkers() {
        didSet { ruler?.needsDisplay = true }
    }

    var lineStarts: [Int] = [0]
    var lineStartsDirty = true
    var ignoreScrollUntil: TimeInterval = 0
    var hasHighlight = false
    var hasFolds = false
    var headings: [OutlineItem] = []
    private(set) var editorFont: EditorFont = .mono
    private(set) var fontSize: Double = Zoom.defaultSize
    private var recolorWork: DispatchWorkItem?

    static let blockHighlight = NSColor.controlAccentColor.withAlphaComponent(0.14)
    static let textHighlight = NSColor.systemYellow.withAlphaComponent(0.45)

    override init() {
        // 줄 위치 계산에 NSLayoutManager 를 쓰므로 TextKit 1 로 만듭니다.
        textView = MdyTextView(usingTextLayoutManager: false)
        scrollView = NSScrollView()
        super.init()

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.layoutManager?.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        // 마크다운 기호가 바뀌지 않도록 자동 치환을 끕니다.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.registerForDraggedTypes([.fileURL, .png, .tiff, .html, .rtf])
        textView.pasteHandler = { [weak self] pasteboard, index in
            self?.handlePaste(pasteboard, at: index) ?? false
        }
        applyFont()

        ruler = LineNumberRuler(scrollView: scrollView, editor: self)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = false

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange(_:)),
                                               name: NSView.frameDidChangeNotification,
                                               object: scrollView.contentView)
    }

    // MARK: 내용·글꼴·색칠

    func setText(_ text: String) {
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        hasFolds = false
        let length = (text as NSString).length
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        applyFont()
        contentDidChange()
    }

    func setFont(_ font: EditorFont, size: Double) {
        guard font != editorFont || size != fontSize else { return }
        editorFont = font
        fontSize = size
        applyFont()
        updateRuler()
    }

    private func applyFont() {
        let font = editorFont.font(size: CGFloat(fontSize))
        textView.font = font
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.foregroundColor] = NSColor.textColor
    }

    /// 글자가 바뀐 뒤: 제목 목록, 색칠, 줄 번호
    private var headingWork: DispatchWorkItem?

    private func contentDidChange() {
        // 제목 목록(접기·줄 번호 옆 ▾용): 긴 문서는 타이핑이 멈췄을 때 다시 셉니다.
        headingWork?.cancel()
        if length < 40_000 {
            headings = DocumentSession.outline(of: textView.string)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.headings = DocumentSession.outline(of: self.textView.string)
                self.ruler?.needsDisplay = true
            }
            headingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        focusRange = nil
        recolor()
        updateRuler()
    }

    func recolor() {
        recolorWork?.cancel()
        // 아주 긴 문서는 타이핑이 멈춘 뒤에 칠합니다.
        if length < 150_000 {
            paint()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.paint() }
            recolorWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func paint() {
        guard let lm = textView.layoutManager else { return }
        if coloring {
            MarkdownColorizer.apply(to: lm, string: textView.string)
        } else {
            MarkdownColorizer.clear(lm, length: length)
        }
        if focusMode { dimOutsideCurrentParagraph(lm) }
    }

    /// 집중 모드에서 마지막으로 진하게 둔 문단 (커서가 같은 문단 안에서 움직이면 다시 칠하지 않아요)
    private var focusRange: NSRange?

    private func currentParagraphRange() -> NSRange {
        ensureLineStarts()
        let count = lineStarts.count
        let caretLine = line(at: textView.selectedRange().location)
        func blank(_ l: Int) -> Bool {
            (textView.string as NSString).substring(with: characterRange(lines: l, l)).trimmingCharacters(in: .whitespaces).isEmpty
        }
        var first = caretLine, last = caretLine
        while first > 0 && !blank(first - 1) { first -= 1 }
        while last + 1 < count && !blank(last + 1) { last += 1 }
        let start = lineStarts[first]
        return NSRange(location: start, length: NSMaxRange(characterRange(lines: last, last)) - start)
    }

    /// 집중 모드: 지금 쓰는 문단(빈 줄 사이)만 진하게
    private func dimOutsideCurrentParagraph(_ lm: NSLayoutManager) {
        let paragraph = currentParagraphRange()
        focusRange = paragraph
        let start = paragraph.location
        let end = NSMaxRange(paragraph)
        let dim = NSColor.tertiaryLabelColor
        if start > 0 { lm.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: 0, length: start)) }
        if end < length { lm.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: end, length: length - end)) }
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    var isFocused: Bool { textView.window?.firstResponder === textView }

    func moveCaret(toLine line: Int) {
        let range = characterRange(lines: line, line)
        revealFolded(at: range.location)
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    // MARK: 줄 번호 표시줄·타자기 모드

    func updateRuler() {
        // 접기 단추(▾)가 늘 보이도록 왼쪽 줄은 항상 켜 둬요 (줄 번호를 끄면 좁아져요).
        scrollView.rulersVisible = true
        ruler?.updateThickness()
        ruler?.needsDisplay = true
    }

    private func updateInsets() {
        let vertical = typewriter ? max(16, scrollView.contentView.bounds.height / 2 - 24) : 16
        if textView.textContainerInset.height != vertical {
            textView.textContainerInset = NSSize(width: 16, height: vertical)
        }
    }

    /// 타자기 모드: 커서 줄을 화면 가운데에 둡니다.
    func centerCaret() {
        guard typewriter, let r = rect(for: NSRange(location: textView.selectedRange().location, length: 0)) else { return }
        scrollTo(y: r.midY - scrollView.contentView.bounds.height / 2)
    }

    @objc private func frameDidChange(_ notification: Notification) {
        if typewriter { updateInsets() }
    }

    // MARK: 줄 번호 ↔ 글자 위치

    var length: Int { (textView.string as NSString).length }

    func ensureLineStarts() {
        guard lineStartsDirty else { return }
        var starts = [0]
        var index = 0
        for unit in textView.string.utf16 {
            index += 1
            if unit == 10 { starts.append(index) }
        }
        lineStarts = starts
        lineStartsDirty = false
    }

    var lineCount: Int { ensureLineStarts(); return lineStarts.count }

    func line(at characterIndex: Int) -> Int {
        ensureLineStarts()
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= characterIndex { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func lineStart(_ line: Int) -> Int {
        ensureLineStarts()
        return lineStarts[max(0, min(line, lineStarts.count - 1))]
    }

    /// s~e 번째 줄(줄바꿈 제외)의 글자 범위
    func characterRange(lines s: Int, _ e: Int) -> NSRange {
        ensureLineStarts()
        let count = lineStarts.count
        let first = max(0, min(s, count - 1))
        let last = max(first, min(e, count - 1))
        let start = lineStarts[first]
        var end = last + 1 < count ? lineStarts[last + 1] - 1 : length
        end = max(start, end)
        return NSRange(location: start, length: end - start)
    }

    func text(ofLine l: Int) -> String {
        (textView.string as NSString).substring(with: characterRange(lines: l, l))
    }

    var caretLine: Int { line(at: textView.selectedRange().location) }

    // MARK: 다른 쪽에서 온 위치 표시

    func clearHighlight() {
        guard hasHighlight, let lm = textView.layoutManager else { return }
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        hasHighlight = false
    }

    /// 미리보기에서 고른 위치를 편집기에 표시합니다. 선택한 글자를 원본에서 찾으면 그 부분을 더 진하게 표시합니다.
    func highlight(lines s: Int, _ e: Int, text: String) {
        guard let lm = textView.layoutManager else { return }
        clearHighlight()
        let block = characterRange(lines: s, e)
        revealFolded(at: block.location)
        lm.addTemporaryAttribute(.backgroundColor, value: Self.blockHighlight, forCharacterRange: block)
        hasHighlight = true

        var target = block
        if let exact = find(text, in: block) {
            lm.addTemporaryAttribute(.backgroundColor, value: Self.textHighlight, forCharacterRange: exact)
            target = exact
        }
        if !isVisible(target) {
            ignoreScrollUntil = Date.timeIntervalSinceReferenceDate + 0.3
            scrollToThird(target)
        }
    }

    func find(_ text: String, in range: NSRange) -> NSRange? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, needle.count <= 1000 else { return nil }
        let source = textView.string as NSString
        let direct = source.range(of: needle, options: [], range: range)
        if direct.location != NSNotFound { return direct }

        // 미리보기 글자 사이에 원본의 마크다운 기호·줄바꿈이 끼어 있어도 찾도록 합니다.
        let markup = "[*_~`=\\\\]*"
        let words = needle.split(whereSeparator: \.isWhitespace).map { word in
            word.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: markup)
        }
        let pattern = words.joined(separator: "(?:\\s|[*_~`=>|#+\\-]|\\d+[.)])+")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return regex.firstMatch(in: source as String, options: [], range: range)?.range
    }

    func rect(for range: NSRange) -> NSRect? {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return nil }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        if range.length == 0 || rect.height == 0 {
            if lm.numberOfGlyphs == 0 || glyphs.location >= lm.numberOfGlyphs {
                rect = lm.extraLineFragmentRect.height > 0 ? lm.extraLineFragmentRect
                    : lm.lineFragmentRect(forGlyphAt: max(0, lm.numberOfGlyphs - 1), effectiveRange: nil)
            } else {
                rect = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            }
        }
        let origin = textView.textContainerOrigin
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    func isVisible(_ range: NSRange) -> Bool {
        guard let r = rect(for: range) else { return true }
        return r.intersects(scrollView.contentView.bounds)
    }

    func scrollToThird(_ range: NSRange) {
        guard let r = rect(for: range) else { return }
        scrollTo(y: r.minY - scrollView.contentView.bounds.height / 3)
    }

    func scrollTo(y: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: 스크롤 동기화

    func scrollPosition() -> ScrollPosition {
        let clip = scrollView.contentView
        let y = clip.bounds.minY
        let maxY = textView.frame.height - clip.bounds.height
        if y <= 0 { return ScrollPosition(line: 0, edge: .top) }
        if y >= maxY - 1 { return ScrollPosition(line: Double(lineCount), edge: .bottom) }

        guard let lm = textView.layoutManager, let tc = textView.textContainer, length > 0 else {
            return ScrollPosition(line: 0, edge: .top)
        }
        let probe = y + (typewriter ? clip.bounds.height / 2 : 0)
        let point = NSPoint(x: 0, y: probe - textView.textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: point, in: tc)
        let index = lm.characterIndexForGlyph(at: glyph)
        let lineNumber = line(at: index)
        guard let r = rect(for: characterRange(lines: lineNumber, lineNumber)) else {
            return ScrollPosition(line: Double(lineNumber), edge: .none)
        }
        let fraction = r.height > 0 ? min(1, max(0, (y - r.minY) / r.height)) : 0
        return ScrollPosition(line: Double(lineNumber) + Double(fraction), edge: .none)
    }

    func scroll(to position: ScrollPosition) {
        ignoreScrollUntil = Date.timeIntervalSinceReferenceDate + 0.25
        switch position.edge {
        case .top:
            scrollTo(y: 0)
        case .bottom:
            scrollTo(y: .greatestFiniteMagnitude)
        case .none:
            let lineNumber = max(0, min(Int(position.line), lineCount - 1))
            guard let r = rect(for: characterRange(lines: lineNumber, lineNumber)) else { return }
            let fraction = position.line - Double(lineNumber)
            scrollTo(y: r.minY + r.height * CGFloat(fraction))
        }
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        ruler?.needsDisplay = true
        guard Date.timeIntervalSinceReferenceDate >= ignoreScrollUntil else { return }
        onScroll?(scrollPosition())
    }

    // MARK: 서식 (⌘B, ⌘I …)

    func replace(_ range: NSRange, with string: String, select selection: NSRange) {
        textView.insertText(string, replacementRange: range)
        textView.setSelectedRange(selection)
    }

    /// 선택 영역을 기호로 감싸거나, 이미 감싸져 있으면 벗깁니다.
    func toggleWrap(_ marker: String) {
        let ns = textView.string as NSString
        let m = (marker as NSString).length
        var sel = textView.selectedRange()

        if sel.location >= m, NSMaxRange(sel) + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            replace(outer, with: ns.substring(with: sel), select: NSRange(location: outer.location, length: sel.length))
            return
        }
        let selected = ns.substring(with: sel)
        if sel.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            replace(sel, with: inner, select: NSRange(location: sel.location, length: (inner as NSString).length))
            return
        }
        if sel.length == 0 {
            let word = textView.selectionRange(forProposedRange: sel, granularity: .selectByWord)
            let text = ns.substring(with: word).trimmingCharacters(in: .whitespacesAndNewlines)
            if word.length > 0, !text.isEmpty, text.allSatisfy({ $0.isLetter || $0.isNumber }) {
                sel = word
            }
        }
        let text = ns.substring(with: sel)
        replace(sel, with: marker + text + marker,
                select: NSRange(location: sel.location + m, length: (text as NSString).length))
    }

    /// [글자](주소) 링크를 만듭니다. 클립보드에 주소가 있으면 그것을 씁니다.
    func insertLink() {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let text = ns.substring(with: sel)
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if Self.isURL(text) {
            replace(sel, with: "[](\(text))", select: NSRange(location: sel.location + 1, length: 0))
        } else if Self.isURL(clip) {
            let result = "[\(text)](\(clip))"
            let caret = text.isEmpty ? NSRange(location: sel.location + 1, length: 0)
                : NSRange(location: sel.location + (result as NSString).length, length: 0)
            replace(sel, with: result, select: caret)
        } else {
            let result = tr("[\(text)](주소)")
            let urlStart = sel.location + (text as NSString).length + 3
            replace(sel, with: result, select: NSRange(location: urlStart, length: 2))
        }
    }

    static func isURL(_ text: String) -> Bool {
        text.range(of: #"^(https?|mailto|ftp):\S+$"#, options: .regularExpression) != nil
    }

    /// 현재 줄의 제목 수준을 바꿉니다 (0 이면 제목 해제).
    func setHeading(_ level: Int) {
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        var line = ns.substring(with: lineRange)
        let newline = line.hasSuffix("\n") ? "\n" : ""
        if !newline.isEmpty { line.removeLast() }
        let body = line.replacingOccurrences(of: #"^ {0,3}#{1,6}[ \t]*"#, with: "", options: .regularExpression)
        let prefix = level > 0 ? String(repeating: "#", count: level) + " " : ""
        let result = prefix + body
        let caret = lineRange.location + (result as NSString).length
        replace(NSRange(location: lineRange.location, length: lineRange.length - (newline.isEmpty ? 0 : 1)),
                with: result, select: NSRange(location: caret, length: 0))
    }

    // MARK: 미리보기에서 온 수정

    /// 원본을 고칩니다. 실행 취소(⌘Z)에 기록되고, 편집기 커서·스크롤은 건드리지 않습니다.
    func applyEdit(_ range: NSRange, _ string: String) {
        ignoreScrollUntil = Date.timeIntervalSinceReferenceDate + 0.3
        guard textView.shouldChangeText(in: range, replacementString: string),
              let storage = textView.textStorage else { return }
        var attributes = textView.typingAttributes
        attributes[.mdyFolded] = nil
        storage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: attributes))
        textView.didChangeText()
    }

    /// s~e 번째 줄을 text 로 바꿉니다 (미리보기에서 블록을 고쳤을 때).
    func replaceLines(_ s: Int, _ e: Int, with text: String) {
        let range = characterRange(lines: s, e)
        guard (textView.string as NSString).substring(with: range) != text else { return }
        applyEdit(range, text)
    }

    private static let taskBox = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\]"#)

    /// 체크리스트 항목의 [ ] ↔ [x] 를 바꿉니다.
    func toggleTask(line: Int) {
        let range = characterRange(lines: line, line)
        let text = (textView.string as NSString).substring(with: range)
        guard let m = Self.taskBox.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return }
        let box = m.range(at: 1)
        let checked = (text as NSString).substring(with: box) != " "
        applyEdit(NSRange(location: range.location + box.location, length: 1), checked ? " " : "x")
    }

    /// 미리보기에서 ⌥ + 두 번 클릭한 자리로 커서를 옮기고 편집기에 포커스를 줍니다.
    func beginEditing(lines s: Int, _ e: Int, text: String) {
        let block = characterRange(lines: s, e)
        revealFolded(at: block.location)
        let target = find(text, in: block) ?? NSRange(location: block.location, length: 0)
        focus()
        textView.setSelectedRange(target)
        if !isVisible(target) {
            ignoreScrollUntil = Date.timeIntervalSinceReferenceDate + 0.3
            scrollToThird(target)
        }
        textView.showFindIndicator(for: target.length > 0 ? target : characterRange(lines: s, s))
    }

    // MARK: 목록 자동 이어쓰기

    private static let listItem = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quoteLine = try! NSRegularExpression(pattern: #"^([ \t]*(?:>[ \t]?)+)"#)

    func currentLine() -> (range: NSRange, text: String)? {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let full = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var range = full
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        return (range, ns.substring(with: range))
    }

    private func continueList() -> Bool {
        guard autoList, textView.selectedRange().length == 0, let (lineRange, line) = currentLine() else { return false }
        let caret = textView.selectedRange().location
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)

        if let m = Self.listItem.firstMatch(in: line, range: whole) {
            let markerEnd = lineRange.location + m.range.length
            guard caret >= markerEnd else { return false }
            let content = ns.substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                replace(lineRange, with: "", select: NSRange(location: lineRange.location, length: 0))
                return true
            }
            let indent = ns.substring(with: m.range(at: 1))
            var marker: String
            if m.range(at: 2).location != NSNotFound {
                marker = ns.substring(with: m.range(at: 2))
            } else {
                let number = Int(ns.substring(with: m.range(at: 3))) ?? 0
                marker = "\(number + 1)" + ns.substring(with: m.range(at: 4))
            }
            let spacing = ns.substring(with: m.range(at: 5))
            let task = m.range(at: 6).location != NSNotFound ? "[ ] " : ""
            let insert = "\n" + indent + marker + spacing + task
            replace(NSRange(location: caret, length: 0), with: insert,
                    select: NSRange(location: caret + (insert as NSString).length, length: 0))
            return true
        }

        if let m = Self.quoteLine.firstMatch(in: line, range: whole) {
            let prefix = ns.substring(with: m.range(at: 1))
            guard caret >= lineRange.location + m.range.length else { return false }
            if ns.substring(from: m.range.length).trimmingCharacters(in: .whitespaces).isEmpty {
                replace(lineRange, with: "", select: NSRange(location: lineRange.location, length: 0))
                return true
            }
            let insert = "\n" + (prefix.hasSuffix(" ") ? prefix : prefix + " ")
            replace(NSRange(location: caret, length: 0), with: insert,
                    select: NSRange(location: caret + (insert as NSString).length, length: 0))
            return true
        }
        return false
    }

    /// 목록 줄에서 Tab / Shift-Tab 으로 들여쓰기·내어쓰기
    private func indentList(_ direction: Int) -> Bool {
        guard autoList, let (lineRange, line) = currentLine() else { return false }
        let ns = line as NSString
        guard let m = Self.listItem.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return false }
        let sel = textView.selectedRange()
        let unit = m.range(at: 2).location != NSNotFound ? 2 : m.range(at: 3).length + m.range(at: 4).length + 1
        if direction > 0 {
            let pad = String(repeating: " ", count: unit)
            replace(NSRange(location: lineRange.location, length: 0), with: pad,
                    select: NSRange(location: sel.location + unit, length: sel.length))
        } else {
            let leading = line.prefix(while: { $0 == " " }).count
            let remove = min(unit, leading)
            guard remove > 0 else { return true }
            replace(NSRange(location: lineRange.location, length: remove), with: "",
                    select: NSRange(location: max(lineRange.location, sel.location - remove), length: sel.length))
        }
        return true
    }

    // MARK: NSTextViewDelegate / NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { lineStartsDirty = true }
    }

    func textDidChange(_ notification: Notification) {
        clearHighlight()
        contentDidChange()
        onChange?(textView.string)
        centerCaret()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): return tableNewline() || continueList()
        case #selector(NSResponder.insertTab(_:)): return tableTab(forward: true) || indentList(1)
        case #selector(NSResponder.insertBacktab(_:)): return tableTab(forward: false) || indentList(-1)
        default: return false
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let selection = textView.selectedRange()
        // 접힌 곳 바로 뒤에서 친 글자가 숨지 않게
        textView.typingAttributes[.mdyFolded] = nil
        if hasFolds { revealFolded(at: selection.location) }

        let first = line(at: selection.location)
        let lineStart = lineStart(first)
        let selectedText = selection.length > 0 && selection.length <= 200_000
            ? (textView.string as NSString).substring(with: selection) : ""
        onCaretChange?(CaretInfo(line: first + 1, column: selection.location - lineStart + 1,
                                 selectedCharacters: selectedText.count,
                                 selectedWords: DocumentSession.wordCount(selectedText)))
        ruler?.needsDisplay = true
        if focusMode, currentParagraphRange() != focusRange { recolor() }

        guard isFocused else { return }
        clearHighlight()
        centerCaret()
        let last = selection.length > 0 ? line(at: NSMaxRange(selection) - 1) : first
        onSelectionChange?(first, last, selection.length <= 2000 ? selectedText : "")
    }
}
