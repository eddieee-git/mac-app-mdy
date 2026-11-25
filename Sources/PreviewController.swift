import AppKit
import UniformTypeIdentifiers
import WebKit

/// 미리보기 웹뷰. 편집 메뉴의 찾기(⌘F, ⌘G …)가 미리보기에 포커스가 있을 때도 동작하게 합니다.
final class MdyWebView: WKWebView {
    var onFindAction: ((NSTextFinder.Action) -> Void)?

    override func performTextFinderAction(_ sender: Any?) {
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        onFindAction?(NSTextFinder.Action(rawValue: tag) ?? .showFindInterface)
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        performTextFinderAction(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performTextFinderAction(_:)) || item.action == #selector(performFindPanelAction(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}

/// 창마다 하나의 WKWebView 를 유지하고, 내용이 바뀌면 HTML 을 다시 불러오지 않고
/// JavaScript 로 본문만 다시 그립니다(스크롤 위치 유지).
@MainActor
final class PreviewController: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: MdyWebView

    // 찾기 막대 상태
    @Published var isFindVisible = false
    @Published var findQuery = ""
    @Published private(set) var findCount = 0
    @Published private(set) var findIndex = -1
    @Published private(set) var findFocusToken = 0

    /// 미리보기에서 클릭·선택했을 때 (시작 줄, 끝 줄, 선택한 글자)
    var onSelect: ((Int, Int, String) -> Void)?
    var onScroll: ((ScrollPosition) -> Void)?
    /// 미리보기를 두 번 클릭했을 때 (시작 줄, 끝 줄, 두 번 클릭으로 고른 단어)
    var onEditRequest: ((Int, Int, String) -> Void)?
    /// 미리보기 안에서 블록을 고쳤을 때 (시작 줄, 끝 줄, 새 내용)
    var onReplaceLines: ((Int, Int, String) -> Void)?
    var onToggleTask: ((Int) -> Void)?
    /// 미리보기의 다른 .md 문서 링크를 눌렀을 때
    var onOpenDocument: ((URL) -> Void)?
    private var pendingAnchor: String?

    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// 앱에 들어 있는 수식·다이어그램 라이브러리 (있으면 오프라인으로 그림)
    static let bundledLibraries: [String] = {
        var names: [String] = []
        if Bundle.main.url(forResource: "katex.min", withExtension: "js", subdirectory: "vendor") != nil,
           Bundle.main.url(forResource: "katex", withExtension: "css", subdirectory: "vendor") != nil { names.append("katex") }
        if Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "vendor") != nil { names.append("mermaid") }
        return names
    }()

    private var isLoaded = false
    private var isRendering = false
    private var pendingText: String?
    private var lastRendered: String?
    private var baseDirectory: URL?
    private var fileURL: URL?
    private var didLoadTemplate = false
    private var zoom: Double = 1
    private var options: [String: Any] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        // 쿠키·캐시를 디스크에 남기지 않아요.
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let handler = ScriptMessageProxy()
        config.userContentController.add(handler, name: "mdy")
        webView = MdyWebView(frame: .zero, configuration: config)
        super.init()
        handler.target = self
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        // 다크 모드에서 로딩 중 흰 화면이 번쩍이지 않도록 합니다.
        webView.setValue(false, forKey: "drawsBackground")
        webView.onFindAction = { [weak self] action in self?.handleFindAction(action) }
    }

    /// 문서 파일 위치를 기준으로 상대 경로 이미지·링크를 해석합니다.
    func setFileURL(_ fileURL: URL?) {
        self.fileURL = fileURL
        let directory = fileURL?.deletingLastPathComponent()
        if didLoadTemplate && directory == baseDirectory { return }
        didLoadTemplate = true
        baseDirectory = directory
        isLoaded = false
        if pendingText == nil { pendingText = lastRendered }
        lastRendered = nil
        // 불러올 때마다 새 nonce: 이 값이 붙은 스크립트(앱이 넣은 것)만 실행돼요.
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        webView.loadHTMLString(Self.template.replacingOccurrences(of: "MDY_NONCE", with: nonce),
                               baseURL: directory ?? Bundle.main.resourceURL)
    }

    private var renderWork: DispatchWorkItem?

    func render(_ text: String) {
        pendingText = text
        renderWork?.cancel()
        // 긴 문서는 타이핑이 잠깐 멈췄을 때 그려요 (글자마다 다시 그리면 느려져요).
        let length = text.utf16.count
        guard length > 40_000, lastRendered != nil else { flush(); return }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (length > 300_000 ? 0.35 : 0.15), execute: work)
    }

    /// 미리보기 안에서 쓰는 화면 글자 (영어일 때만 번역표를 넘겨요)
    static let pageStrings: [String: String] = {
        guard Loc.isEnglish else { return [:] }
        // 미리보기(preview.html · markdown.js)의 T('…') 키. 번역은 en.json 에 있어요.
        let keys = ["복사", "복사됨", "마크다운으로 쓰세요", "원본 {}줄 · 다 고쳤으면 ⌘↩ 또는 바깥 클릭 · esc 는 취소", // no-tr
                    "내용이 없어요", "외부 이미지 {}개를 막았어요", "불러오기", "미리보기를 두 번 클릭하면 그 자리에서 고칠 수 있어요", // no-tr
                    "알겠어요", "참고", "팁", "중요", "경고", "주의", "본문으로"] // no-tr
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, Loc.translate($0, [])) })
    }()

    var onDismissTip: (() -> Void)?

    func setFontSize(_ size: Double) {
        zoom = size / Zoom.defaultSize
        webView.pageZoom = CGFloat(zoom)
    }

    /// font: sans|serif, width: narrow|normal|wide|full, theme: github|paper, rich: Bool
    func setOptions(_ options: [String: Any]) {
        var options = options
        options["bundled"] = Self.bundledLibraries
        options["strings"] = Self.pageStrings
        self.options = options
        call("mdySetOptions", [options])
    }

    /// 다른 문서의 #제목 링크로 들어왔을 때 그 제목으로 이동합니다.
    func scrollToAnchor(_ id: String) {
        guard isLoaded, lastRendered != nil, pendingText == nil, !isRendering else { pendingAnchor = id; return }
        call("mdyScrollToAnchor", [id])
    }

    /// 웹·문서 앱에서 복사한 HTML → 마크다운
    func htmlToMarkdown(_ html: String, completion: @escaping (String?) -> Void) {
        guard isLoaded else { completion(nil); return }
        webView.callAsyncJavaScript("return MdyConvert.htmlToMarkdown(h)", arguments: ["h": html], in: nil, in: .page) { result in
            if case .success(let value) = result { completion(value as? String) } else { completion(nil) }
        }
    }

    /// 다른 앱에 붙여넣을 서식 있는 HTML. markdown 이 nil 이면 문서 전체.
    func richHTML(markdown: String?, completion: @escaping (String?) -> Void) {
        guard isLoaded else { completion(nil); return }
        webView.callAsyncJavaScript("return mdyRichHTML(m)", arguments: ["m": markdown ?? NSNull()], in: nil, in: .page) { result in
            if case .success(let value) = result { completion(value as? String) } else { completion(nil) }
        }
    }

    private func provideLibrary(_ name: String) {
        func read(_ file: String, _ ext: String) -> String? {
            guard let url = Bundle.main.url(forResource: file, withExtension: ext, subdirectory: "vendor") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        let script = name == "katex" ? read("katex.min", "js") : read("mermaid.min", "js")
        let css = name == "katex" ? read("katex", "css") : nil
        guard let script else { return }
        call("mdyProvideLib", [name, script, css ?? ""])
    }

    /// 편집기 커서·선택 위치를 미리보기에 표시합니다(화면 밖이면 그쪽으로 이동).
    func highlight(lines s: Int, _ e: Int, text: String) {
        call("mdyHighlight", [s, e, text, true])
    }

    func scroll(to position: ScrollPosition) {
        call("mdyScrollToLine", [position.line, position.edge.rawValue])
    }

    // MARK: 찾기

    func showFind() {
        isFindVisible = true
        findFocusToken += 1
        if !findQuery.isEmpty { find(step: 0) }
    }

    func hideFind() {
        isFindVisible = false
        findCount = 0
        findIndex = -1
        call("mdyFindClear", [])
        webView.window?.makeFirstResponder(webView)
    }

    /// step: 0 = 새로 찾기, 1 = 다음, -1 = 이전
    func find(step: Int) {
        guard isLoaded else { return }
        webView.callAsyncJavaScript("return mdyFind(q, step)", arguments: ["q": findQuery, "step": step],
                                    in: nil, in: .page) { [weak self] result in
            guard case .success(let value) = result, let dict = value as? [String: Any] else { return }
            self?.findCount = (dict["count"] as? NSNumber)?.intValue ?? 0
            self?.findIndex = (dict["index"] as? NSNumber)?.intValue ?? -1
        }
    }

    private func handleFindAction(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface, .showReplaceInterface: showFind()
        case .nextMatch: isFindVisible ? find(step: 1) : showFind()
        case .previousMatch: isFindVisible ? find(step: -1) : showFind()
        case .hideFindInterface: hideFind()
        case .setSearchString:
            webView.evaluateJavaScript("getSelection().toString()") { [weak self] value, _ in
                guard let self, let text = value as? String, !text.isEmpty else { return }
                self.findQuery = text
                self.showFind()
            }
        default: break
        }
    }

    // MARK: 프린트·내보내기

    private var documentTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? tr("제목 없음")
    }

    var canPrint: Bool { webView.bounds.width > 50 }

    func printDocument() {
        guard let window = webView.window, canPrint else { NSSound.beep(); return }
        let operation = webView.printOperation(with: Self.printInfo())
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func exportPDF() {
        guard let window = webView.window, canPrint else { NSSound.beep(); return }
        let panel = savePanel(type: .pdf, ext: "pdf")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let info = Self.printInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            let operation = self.webView.printOperation(with: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = true
            operation.view?.frame = self.webView.bounds
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    func exportHTML() {
        guard let window = webView.window, isLoaded else { NSSound.beep(); return }
        webView.callAsyncJavaScript("return mdyExportHTML(t)", arguments: ["t": documentTitle],
                                    in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result, let html = value as? String else { NSSound.beep(); return }
            let panel = self.savePanel(type: .html, ext: "html")
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try Data(html.utf8).write(to: url, options: .atomic)
                } catch {
                    NSAlert(error: error).beginSheetModal(for: window)
                }
            }
        }
    }

    enum OfficeFormat { case word, rtf }

    /// Word(.docx)·RTF 로 내보내기. 다른 앱에 붙여 넣을 때와 같은 깔끔한 서식을 macOS 문서 변환기로 바꿔요.
    /// (다이어그램 그림과 수식은 Word 에서 그릴 수 없어서 수식은 TeX 글자로, 다이어그램은 빠져요.)
    func exportOffice(_ format: OfficeFormat) {
        guard let window = webView.window, isLoaded else { NSSound.beep(); return }
        richHTML(markdown: nil) { [weak self] html in
            guard let self, let html else { NSSound.beep(); return }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
            if let base = self.baseDirectory { options[.baseURL] = base }
            guard let attributed = try? NSAttributedString(data: Data(html.utf8), options: options, documentAttributes: nil) else {
                NSSound.beep(); return
            }
            let type: UTType = format == .word ? (UTType(filenameExtension: "docx") ?? .data) : .rtf
            let panel = self.savePanel(type: type, ext: format == .word ? "docx" : "rtf")
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    let documentType: NSAttributedString.DocumentType = format == .word ? .officeOpenXML : .rtf
                    let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                                   documentAttributes: [.documentType: documentType])
                    try data.write(to: url, options: .atomic)
                } catch {
                    NSAlert(error: error).beginSheetModal(for: window)
                }
            }
        }
    }

    private func savePanel(type: UTType, ext: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = documentTitle + "." + ext
        panel.directoryURL = baseDirectory
        return panel
    }

    private static func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        return info
    }

    // MARK: JavaScript 연결

    private func call(_ function: String, _ arguments: [Any]) {
        guard isLoaded,
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("\(function)(...\(json))", completionHandler: nil)
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "select":
            let start = (message["start"] as? NSNumber)?.intValue ?? 0
            let end = (message["end"] as? NSNumber)?.intValue ?? start
            onSelect?(start, end, message["text"] as? String ?? "")
        case "scroll":
            let line = (message["line"] as? NSNumber)?.doubleValue ?? 0
            let edge = ScrollPosition.Edge(rawValue: message["edge"] as? String ?? "") ?? .none
            onScroll?(ScrollPosition(line: line, edge: edge))
        case "edit":
            let start = (message["start"] as? NSNumber)?.intValue ?? 0
            let end = (message["end"] as? NSNumber)?.intValue ?? start
            onEditRequest?(start, end, message["text"] as? String ?? "")
        case "replaceLines":
            let start = (message["start"] as? NSNumber)?.intValue ?? 0
            let end = (message["end"] as? NSNumber)?.intValue ?? start
            onReplaceLines?(start, end, message["text"] as? String ?? "")
        case "toggleTask":
            if let line = (message["line"] as? NSNumber)?.intValue { onToggleTask?(line) }
        case "copyText":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message["text"] as? String ?? "", forType: .string)
        case "dismissTip":
            onDismissTip?()
        case "needLib":
            if let name = message["name"] as? String { provideLibrary(name) }
        case "find":
            findCount = (message["count"] as? NSNumber)?.intValue ?? 0
            findIndex = (message["index"] as? NSNumber)?.intValue ?? -1
        default:
            break
        }
    }

    private func flush() {
        guard isLoaded, !isRendering, let text = pendingText else { return }
        pendingText = nil
        guard text != lastRendered else { return }
        lastRendered = text
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else { return }
        isRendering = true
        webView.evaluateJavaScript("renderMarkdown(\(json))") { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isRendering = false
                if self.pendingText == nil, let anchor = self.pendingAnchor {
                    self.pendingAnchor = nil
                    self.call("mdyScrollToAnchor", [anchor])
                }
                self.flush()
            }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        webView.pageZoom = CGFloat(zoom)
        if !options.isEmpty { call("mdySetOptions", [options]) }
        flush()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // 링크는 미리보기 안에서 이동하지 않고, 기본 앱(브라우저·Mdy 등)으로 엽니다.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            // 다른 마크다운 문서는 Mdy 안에서 (탭으로) 열고, 나머지는 기본 앱으로
            if url.isFileURL, Self.markdownExtensions.contains(url.pathExtension.lowercased()), let open = onOpenDocument {
                open(url)
            } else {
                LinkSafety.open(url, in: webView.window)
            }
            return .cancel
        }
        // 링크가 아닌 이동(스크립트·자동 새로 고침 등)은 처음 불러오기 말고는 막아요.
        if navigationAction.navigationType == .other, navigationAction.targetFrame?.isMainFrame == true,
           isLoaded, navigationAction.request.url?.absoluteString != "about:blank" {
            return .cancel
        }
        return .allow
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        didLoadTemplate = false
        setFileURL(fileURL)
    }

    // MARK: Template

    static let template: String = {
        func resource(_ name: String, _ ext: String) -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return text
        }
        return resource("preview", "html")
            .replacingOccurrences(of: "/*MARKDOWN_JS*/",
                                  with: [resource("highlight", "js"), resource("markdown", "js"), resource("convert", "js")].joined(separator: "\n"))
    }()
}

/// WKUserContentController 가 핸들러를 강하게 붙잡으므로, 순환 참조를 피하려고 약한 참조로 전달합니다.
@MainActor
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: PreviewController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message.body)
    }
}
