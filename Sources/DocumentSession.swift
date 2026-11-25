import SwiftUI

struct OutlineItem: Identifiable, Equatable {
    let line: Int
    let level: Int
    let title: String
    var id: Int { line }
}

struct DocumentStats: Equatable {
    var words = 0
    var characters = 0
    var charactersNoSpaces = 0
    var lines = 1
}

struct CaretInfo: Equatable {
    var line = 1
    var column = 1
    var selectedCharacters = 0
    var selectedWords = 0
}

/// 창 하나의 편집기·미리보기와 둘 사이의 연결(선택 위치 표시, 스크롤 동기화),
/// 목차·통계를 맡습니다.
@MainActor
final class DocumentSession: ObservableObject {
    let editor = EditorController()
    let preview = PreviewController()

    @Published private(set) var outline: [OutlineItem] = []
    @Published private(set) var currentHeading: Int?
    @Published private(set) var stats = DocumentStats()
    @Published private(set) var caret = CaretInfo()

    /// 두 패널이 모두 보이고 스크롤 동기화가 켜져 있을 때만 스크롤을 맞춥니다.
    var linksScrolling = false

    // MARK: 파일 지켜보기 · 바뀐 줄

    /// 다른 앱에서 바뀐 내용을 문서에 넣을 때 (화면 쪽에서 문서 바인딩에 씁니다)
    var onExternalReload: ((String) -> Void)?
    /// 다른 앱에서 바뀌었는데 이쪽에도 저장 안 된 수정이 있을 때
    @Published private(set) var externalConflict = false
    @Published private(set) var changeBaseLabel = tr("문서를 연 때")
    @Published private(set) var changeCounts = (added: 0, modified: 0, deleted: 0)

    private(set) var fileURL: URL?
    private var watcher: FileWatcher?
    private var lastDiskText: String?
    private var pendingDiskText: String?
    private var recentTexts: [Int] = []
    private var baseText: String?
    private var changeWork: DispatchWorkItem?
    private var diskWork: DispatchWorkItem?
    private var anchorObserver: NSObjectProtocol?
    private var lineObserver: NSObjectProtocol?

    /// 폴더 검색 결과로 그 줄로 가서, 찾은 글자를 양쪽에 표시해요.
    func jump(toLine line: Int, query: String) {
        editor.moveCaret(toLine: line)
        editor.highlight(lines: line, line, text: query)
        preview.highlight(lines: line, line, text: query)
        let position = ScrollPosition(line: max(0, Double(line) - 3), edge: .none)
        editor.scroll(to: position)
        preview.scroll(to: position)
    }

    func setFile(_ url: URL?, currentText: String) {
        guard url?.standardizedFileURL != fileURL?.standardizedFileURL else { return }
        fileURL = url
        editor.documentURL = url
        preview.setFileURL(url)
        if lastDiskText == nil { lastDiskText = currentText }
        if baseText == nil { baseText = currentText }
        watcher = url.map { FileWatcher(url: $0) { [weak self] in self?.fileChangedOnDisk() } }
        refreshGitBase()
        if let url, let anchor = Navigator.shared.takeAnchor(for: url) { preview.scrollToAnchor(anchor) }
        if let url, let target = Navigator.shared.takeLine(for: url) {
            // 새로 연 문서: 미리보기가 그려진 뒤에 이동
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.jump(toLine: target.line, query: target.query) }
        }
    }

    func refreshGitBase() {
        guard let url = fileURL else { return }
        Task {
            if let head = await GitBase.headContent(of: url) {
                baseText = head
                changeBaseLabel = tr("git 마지막 커밋")
            }
            scheduleChangeMarkers()
        }
    }

    private func scheduleChangeMarkers() {
        changeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = self.editor.textView.string
            let base = self.baseText ?? current
            // 비교는 뒤에서 하고, 그사이 글이 또 바뀌었으면 버려요.
            Task.detached(priority: .utility) {
                let markers = ChangeMarkers.compute(base: base, current: current)
                await MainActor.run {
                    guard self.editor.textView.string == current else { return }
                    self.editor.changeMarkers = markers
                    self.changeCounts = (markers.added, markers.modified, markers.deletions.count)
                }
            }
        }
        changeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func fileChangedOnDisk() {
        diskWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkDisk() }
        diskWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func checkDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let disk = MarkdownDocument.decode(data)
        let current = editor.textView.string
        refreshGitBase()
        if disk == current || recentTexts.contains(disk.hashValue) {
            // 이쪽에서 저장한 내용
            lastDiskText = disk
            return
        }
        if current == lastDiskText {
            reload(disk)
        } else {
            pendingDiskText = disk
            externalConflict = true
        }
    }

    private func reload(_ text: String) {
        lastDiskText = text
        externalConflict = false
        pendingDiskText = nil
        onExternalReload?(text)
    }

    /// 충돌 막대: 디스크 내용으로 다시 불러오기
    func reloadFromDisk() {
        if let text = pendingDiskText { reload(text) }
    }

    /// 충돌 막대: 이쪽 내용 유지 (다음 저장 때 덮어씀)
    func keepMine() {
        lastDiskText = pendingDiskText
        pendingDiskText = nil
        externalConflict = false
    }

    // MARK: 복사

    /// 서식 있는 텍스트로 복사: 편집기에서 선택한 부분, 없으면 문서 전체
    func copyRich() {
        let sel = editor.textView.selectedRange()
        let selected = sel.length > 0 && editor.isFocused ? (editor.textView.string as NSString).substring(with: sel) : nil
        let markdown = selected ?? editor.textView.string
        preview.richHTML(markdown: selected) { html in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let html { pasteboard.setString(html, forType: .html) }
            pasteboard.setString(markdown, forType: .string)
        }
    }

    /// 미리보기를 두 번 클릭했을 때 (원본 줄). 화면 쪽에서 편집기를 보이게 한 뒤 editAt 을 부릅니다.
    var onEditRequest: ((Int) -> Void)?
    private var pendingEdit: (start: Int, end: Int, text: String)?

    func editAt(line: Int) {
        let edit = pendingEdit ?? (line, line, "")
        pendingEdit = nil
        editor.beginEditing(lines: edit.start, edit.end, text: edit.text)
    }

    init() {
        editor.richPasteConverter = { [weak self] html, completion in
            guard let self else { completion(nil); return }
            self.preview.htmlToMarkdown(html, completion: completion)
        }
        preview.onOpenDocument = { [weak self] url in
            Navigator.shared.follow(from: self?.fileURL, to: url)
        }
        anchorObserver = NotificationCenter.default.addObserver(forName: .mdyScrollToAnchor, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let url = note.object as? URL, url == self.fileURL?.standardizedFileURL,
                      let id = note.userInfo?["id"] as? String else { return }
                self.preview.scrollToAnchor(id)
            }
        }
        lineObserver = NotificationCenter.default.addObserver(forName: .mdyJumpToLine, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let url = note.object as? URL, url == self.fileURL?.standardizedFileURL,
                      let line = note.userInfo?["line"] as? Int else { return }
                self.jump(toLine: line, query: note.userInfo?["query"] as? String ?? "")
            }
        }
        preview.onReplaceLines = { [weak self] s, e, text in
            self?.editor.replaceLines(s, e, with: text)
        }
        preview.onToggleTask = { [weak self] line in
            self?.editor.toggleTask(line: line)
        }
        preview.onEditRequest = { [weak self] s, e, text in
            self?.pendingEdit = (s, e, text)
            self?.onEditRequest?(s)
        }
        editor.onSelectionChange = { [weak self] s, e, text in
            self?.preview.highlight(lines: s, e, text: text)
        }
        editor.onCaretChange = { [weak self] info in
            self?.caret = info
        }
        preview.onSelect = { [weak self] s, e, text in
            self?.editor.highlight(lines: s, e, text: text)
        }
        editor.onScroll = { [weak self] position in
            guard let self else { return }
            self.updateCurrentHeading(position)
            if self.linksScrolling { self.preview.scroll(to: position) }
        }
        preview.onScroll = { [weak self] position in
            guard let self else { return }
            self.updateCurrentHeading(position)
            if self.linksScrolling { self.editor.scroll(to: position) }
        }
    }

    func textDidChange(_ text: String) {
        editor.setText(text)
        preview.render(text)
        scheduleAnalysis(text)
        // 이쪽에서 만든 내용인지 나중에 알아보려고 최근 내용을 기억합니다 (자동 저장이 파일을 바꿀 때 구분용)
        recentTexts.append(text.hashValue)
        if recentTexts.count > 400 { recentTexts.removeFirst(recentTexts.count - 400) }
        scheduleChangeMarkers()
    }

    private var analysisWork: DispatchWorkItem?

    /// 목차·글자 수: 짧은 문서는 바로, 긴 문서는 타이핑이 잠깐 멈췄을 때 뒤에서 세요.
    private func scheduleAnalysis(_ text: String) {
        analysisWork?.cancel()
        if text.utf16.count < 40_000 {
            applyAnalysis(Self.outline(of: text), Self.stats(of: text))
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task.detached(priority: .userInitiated) {
                let outline = DocumentSession.outline(of: text)
                let stats = DocumentSession.stats(of: text)
                await MainActor.run { self?.applyAnalysis(outline, stats) }
            }
        }
        analysisWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func applyAnalysis(_ newOutline: [OutlineItem], _ newStats: DocumentStats) {
        if newOutline != outline { outline = newOutline }
        if newStats != stats { stats = newStats }
    }

    func alignPreviewToEditor() {
        guard linksScrolling else { return }
        preview.scroll(to: editor.scrollPosition())
    }

    /// 목차에서 제목을 고르면 양쪽 모두 그 제목으로 이동합니다.
    func jump(to item: OutlineItem) {
        let position = ScrollPosition(line: Double(item.line), edge: item.line == 0 ? .top : .none)
        editor.moveCaret(toLine: item.line)
        editor.scroll(to: position)
        preview.scroll(to: position)
        currentHeading = item.id
    }

    private func updateCurrentHeading(_ position: ScrollPosition) {
        let line: Double = switch position.edge {
        case .top: 0
        case .bottom: .greatestFiniteMagnitude
        case .none: position.line + 0.5
        }
        let current = outline.last(where: { Double($0.line) <= line })?.id ?? outline.first?.id
        if current != currentHeading { currentHeading = current }
    }

    // MARK: 분석

    nonisolated static func outline(of text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var fence: Character?
        var fenceLength = 0
        var previous = ""
        var inFrontMatter = false

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw[...]
            let trimmed = line.drop(while: { $0 == " " })
            defer { previous = String(line) }

            if index == 0 && line == "---" { inFrontMatter = true; continue }
            if inFrontMatter {
                if line == "---" || line == "..." { inFrontMatter = false }
                continue
            }

            // 코드 블록 안의 # 은 제목이 아님
            if let first = trimmed.first, first == "`" || first == "~", line.count - trimmed.count <= 3 {
                let run = trimmed.prefix(while: { $0 == first }).count
                if run >= 3 {
                    if fence == nil { fence = first; fenceLength = run }
                    else if fence == first && run >= fenceLength && trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
                    continue
                }
            }
            if fence != nil { continue }

            if line.count - trimmed.count <= 3, trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(hashes)
                if hashes <= 6, rest.isEmpty || rest.first == " " || rest.first == "\t" {
                    var title = rest.trimmingCharacters(in: .whitespaces)
                    while title.hasSuffix("#") { title = String(title.dropLast()) }
                    items.append(OutlineItem(line: index, level: hashes, title: plain(title)))
                    continue
                }
            }

            // Setext 제목: 문단 다음 줄의 === / ---
            let underline = trimmed.trimmingCharacters(in: .whitespaces)
            if !underline.isEmpty, line.count - trimmed.count <= 3,
               underline.allSatisfy({ $0 == "=" }) || underline.allSatisfy({ $0 == "-" }) {
                let prev = previous.trimmingCharacters(in: .whitespaces)
                let isParagraph = !prev.isEmpty && !prev.hasPrefix("#") && !prev.hasPrefix(">") &&
                    !prev.hasPrefix("- ") && !prev.hasPrefix("* ") && !prev.hasPrefix("+ ") && !prev.hasPrefix("|")
                if isParagraph, !items.contains(where: { $0.line == index - 1 }) {
                    items.append(OutlineItem(line: index - 1, level: underline.first == "=" ? 1 : 2, title: plain(prev)))
                }
            }
        }
        return items
    }

    /// 제목에서 마크다운 기호를 걷어냅니다.
    nonisolated private static func plain(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[*_`~]|=="#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return s.isEmpty ? tr("(제목 없음)") : s
    }

    nonisolated static func stats(of text: String) -> DocumentStats {
        var stats = DocumentStats()
        var inWord = false
        for scalar in text.unicodeScalars {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if scalar == "\n" { stats.lines += 1 }
            if isSpace {
                inWord = false
            } else {
                if !inWord { stats.words += 1 }
                inWord = true
            }
        }
        stats.characters = text.count
        stats.charactersNoSpaces = text.filter { !$0.isWhitespace }.count
        return stats
    }

    nonisolated static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
