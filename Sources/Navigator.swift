import AppKit

extension Notification.Name {
    static let mdyScrollToAnchor = Notification.Name("MdyScrollToAnchor")
    /// 폴더 검색에서 고른 줄로 (userInfo: line, query)
    static let mdyJumpToLine = Notification.Name("MdyJumpToLine")
}

/// 문서 사이 이동: 링크 따라가기, 뒤로(⌘[)·앞으로(⌘]), 다른 문서의 #제목으로 이동
@MainActor
final class Navigator {
    static let shared = Navigator()

    private var back: [URL: [URL]] = [:]
    private var forward: [URL: [URL]] = [:]
    private var pendingAnchors: [URL: String] = [:]
    private var pendingLines: [URL: (line: Int, query: String)] = [:]

    private func key(_ url: URL) -> URL { url.standardizedFileURL }

    /// 링크를 따라 다른 문서로 갑니다. 지금 문서는 뒤로 가기 목록에 들어갑니다.
    func follow(from current: URL?, to target: URL) {
        var components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        let fragment = components?.fragment
        components?.fragment = nil
        let file = key(components?.url ?? target)
        guard FileManager.default.fileExists(atPath: file.path) else {
            let alert = NSAlert()
            alert.messageText = tr("문서를 찾을 수 없어요")
            alert.informativeText = file.path
            alert.runModal()
            return
        }
        if let current, key(current) != file {
            back[file] = (back[key(current)] ?? []) + [key(current)]
            forward[file] = []
        }
        open(file, anchor: fragment)
    }

    func canGoBack(from current: URL?) -> Bool { current.map { !(back[key($0)] ?? []).isEmpty } ?? false }
    func canGoForward(from current: URL?) -> Bool { current.map { !(forward[key($0)] ?? []).isEmpty } ?? false }

    func goBack(from current: URL?) {
        guard let current = current.map(key), var stack = back[current], let previous = stack.popLast() else { NSSound.beep(); return }
        back[previous] = stack
        forward[previous] = [current] + (forward[current] ?? [])
        open(previous, anchor: nil)
    }

    func goForward(from current: URL?) {
        guard let current = current.map(key), var stack = forward[current], !stack.isEmpty else { NSSound.beep(); return }
        let next = stack.removeFirst()
        back[next] = (back[current] ?? []) + [current]
        forward[next] = stack
        open(next, anchor: nil)
    }

    /// 문서를 엽니다. 이미 열려 있으면 그 창(탭)을 앞으로 가져옵니다.
    func open(_ url: URL, anchor: String? = nil, line: Int? = nil, query: String = "") {
        if let anchor, !anchor.isEmpty { pendingAnchors[key(url)] = anchor }
        if let line { pendingLines[key(url)] = (line, query) }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, alreadyOpen, error in
            Task { @MainActor in
                if let error { NSAlert(error: error).runModal(); return }
                // 이미 열려 있던 문서는 창이 새로 뜨지 않으므로 직접 알려 줍니다.
                if alreadyOpen, let anchor = self?.takeAnchor(for: url) {
                    NotificationCenter.default.post(name: .mdyScrollToAnchor, object: url.standardizedFileURL, userInfo: ["id": anchor])
                }
                if alreadyOpen, let target = self?.takeLine(for: url) {
                    NotificationCenter.default.post(name: .mdyJumpToLine, object: url.standardizedFileURL,
                                                    userInfo: ["line": target.line, "query": target.query])
                }
            }
        }
    }

    func takeAnchor(for url: URL) -> String? {
        pendingAnchors.removeValue(forKey: key(url))
    }

    func takeLine(for url: URL) -> (line: Int, query: String)? {
        pendingLines.removeValue(forKey: key(url))
    }
}
