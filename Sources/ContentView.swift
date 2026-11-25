import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @StateObject private var session = DocumentSession()

    @AppStorage(Pref.lastViewMode) private var lastViewMode: ViewMode = .split
    /// 새 창이 처음 쓸 비율 (마지막으로 쓴 비율을 기억)
    @AppStorage("splitFraction") private var defaultFraction: Double = 0.5
    /// 창마다 따로 쓰는 비율
    @State private var splitFraction: Double = 0.5
    @AppStorage(Pref.syncScroll) private var syncScroll = true
    @AppStorage(Pref.showOutline) private var showSidebar = false
    @AppStorage(Pref.showStatusBar) private var showStatusBar = true
    @AppStorage(Pref.fontSize) private var fontSize: Double = Zoom.defaultSize
    @AppStorage(Pref.editorFont) private var editorFont: EditorFont = .mono
    @AppStorage(Pref.editorColoring) private var editorColoring = true
    @AppStorage(Pref.autoList) private var autoList = true
    @AppStorage(Pref.autoPair) private var autoPair = true
    @AppStorage(Pref.convertRichPaste) private var convertRichPaste = true
    @AppStorage(Pref.lineNumbers) private var lineNumbers = false
    @AppStorage(Pref.showChanges) private var showChanges = true
    @AppStorage(Pref.focusMode) private var focusMode = false
    @AppStorage(Pref.typewriter) private var typewriter = false
    @AppStorage(Pref.imageFolder) private var imageFolder = "images"
    @AppStorage(Pref.previewFont) private var previewFont = "sans"
    @AppStorage(Pref.previewWidth) private var previewWidth = "normal"
    @AppStorage(Pref.previewTheme) private var previewTheme = "github"
    @AppStorage(Pref.richContent) private var richContent = true
    @AppStorage(Pref.appearance) private var appearance: AppAppearance = .system
    @AppStorage(Pref.openInTabs) private var openInTabs = true
    @AppStorage(Pref.rootFolder) private var rootFolder = ""
    @AppStorage(Pref.spellCheck) private var spellCheck = false
    @AppStorage(Pref.blockRemoteImages) private var blockRemoteImages = false
    @AppStorage(Pref.editTip) private var editTip = true

    @State private var mode: ViewMode = .split
    @State private var didSetUp = false
    @State private var showQuickOpen = false

    var body: some View {
        settingsObservers(stateObservers(layout))
    }

    private var workspaceRoot: URL? {
        _ = rootFolder
        return Workspace.root(for: fileURL)
    }

    private var layout: some View {
        VStack(spacing: 0) {
            if session.externalConflict {
                ConflictBanner(session: session)
            }
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView(session: session, fileURL: fileURL, root: workspaceRoot)
                        .frame(width: 240)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                SplitPanes(mode: $mode, fraction: $splitFraction) {
                    HostedView(view: session.editor.scrollView)
                } right: {
                    PreviewPane(preview: session.preview)
                }
            }
            if showStatusBar {
                StatusBar(session: session, mode: mode, showChanges: showChanges)
            }
        }
        .frame(minWidth: 560, minHeight: 320)
        .background(WindowAccessor { window in
            window.tabbingIdentifier = "MdyDocuments"
            window.tabbingMode = openInTabs ? .preferred : .automatic
        })
        .sheet(isPresented: $showQuickOpen) {
            QuickOpenView(model: workspaceRoot.map(FolderModel.model(for:)))
        }
    }

    /// 창 상태(모드·비율·문서)가 바뀔 때
    private func stateObservers(_ content: some View) -> some View {
        content
        .toolbar { toolbar }
        .focusedSceneValue(\.viewMode, $mode)
        .focusedSceneValue(\.preview, session.preview)
        .focusedSceneValue(\.editor, session.editor)
        .focusedSceneValue(\.session, session)
        .focusedSceneValue(\.splitFraction, $splitFraction)
        .focusedSceneValue(\.quickOpen, $showQuickOpen)
        .onAppear(perform: setUp)
        .onChange(of: splitFraction) { _, f in defaultFraction = f }
        .onChange(of: document.text) { _, text in session.textDidChange(text) }
        .onChange(of: fileURL) { _, url in session.setFile(url, currentText: document.text) }
        .onChange(of: mode) { _, newMode in
            lastViewMode = newMode
            updateLinking()
            moveFocus(for: newMode)
            if newMode == .split {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { session.alignPreviewToEditor() }
            }
        }
        .onChange(of: syncScroll) { _, on in
            updateLinking()
            if on { session.alignPreviewToEditor() }
        }
    }

    /// 설정 창에서 값이 바뀔 때
    private func settingsObservers(_ content: some View) -> some View {
        previewObservers(editorObservers(content))
    }

    private func editorObservers(_ content: some View) -> some View {
        content
        .onChange(of: fontSize) { applyEditorSettings(); session.preview.setFontSize(fontSize) }
        .onChange(of: editorFont) { applyEditorSettings() }
        .onChange(of: editorColoring) { applyEditorSettings() }
        .onChange(of: autoList) { applyEditorSettings() }
        .onChange(of: autoPair) { applyEditorSettings() }
        .onChange(of: convertRichPaste) { applyEditorSettings() }
        .onChange(of: lineNumbers) { applyEditorSettings() }
        .onChange(of: showChanges) { applyEditorSettings() }
        .onChange(of: focusMode) { applyEditorSettings() }
        .onChange(of: typewriter) { applyEditorSettings() }
        .onChange(of: imageFolder) { applyEditorSettings() }
        .onChange(of: spellCheck) { applyEditorSettings() }
    }

    private func previewObservers(_ content: some View) -> some View {
        content
        .onChange(of: previewFont) { applyPreviewSettings() }
        .onChange(of: previewWidth) { applyPreviewSettings() }
        .onChange(of: previewTheme) { applyPreviewSettings() }
        .onChange(of: richContent) { applyPreviewSettings() }
        .onChange(of: blockRemoteImages) { applyPreviewSettings() }
        .onChange(of: editTip) { applyPreviewSettings() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Toggle(isOn: $showSidebar.animation(.easeInOut(duration: 0.2))) {
                Label(tr("사이드바"), systemImage: "sidebar.squares.left")
            }
            .help(tr("사이드바(목차·파일) 보이기/가리기 (⌃⌘S)"))
            Toggle(isOn: paneBinding(.left)) {
                Label(tr("원본"), systemImage: "sidebar.left")
            }
            .help(tr("원본(편집기) 패널 보이기/가리기"))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker(tr("원본 : 미리보기 비율"), selection: presetBinding) {
                ForEach(SplitPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.symbol)
                        .tag(Optional(preset))
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help(tr("원본 : 미리보기 비율 — 1:3, 1:1, 3:1 (⌥⌘1, ⌥⌘2, ⌥⌘3)"))

            Toggle(isOn: $syncScroll) {
                Label(tr("스크롤 동기화"), systemImage: "arrow.up.and.down.text.horizontal")
            }
            .help(tr("양쪽 스크롤 위치 맞추기 (⌥⌘L)"))
            .disabled(mode != .split)

            Toggle(isOn: paneBinding(.right)) {
                Label(tr("미리보기"), systemImage: "sidebar.right")
            }
            .help(tr("미리보기 패널 보이기/가리기"))
        }
    }

    /// 비율 버튼: 지금 비율과 맞는 버튼이 눌린 상태로 보이고, 누르면 나란히 보기로 바꾸며 그 비율로 맞춥니다.
    private var presetBinding: Binding<SplitPreset?> {
        Binding(
            get: { mode == .split ? SplitPreset.matching(splitFraction) : nil },
            set: { preset in
                guard let preset else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = .split
                    splitFraction = preset.fraction
                }
            }
        )
    }

    private enum Side { case left, right }

    /// 툴바 버튼: 한쪽을 가리면 다른 쪽만, 다시 켜면 나란히. 둘 다 가릴 수는 없습니다.
    private func paneBinding(_ side: Side) -> Binding<Bool> {
        Binding(
            get: { side == .left ? mode != .preview : mode != .editor },
            set: { visible in
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch (side, visible) {
                    case (.left, true), (.right, true): mode = .split
                    case (.left, false): mode = .preview
                    case (.right, false): mode = .editor
                    }
                }
            }
        )
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        appearance.apply()
        WelcomeWindow.close()
        session.preview.onDismissTip = { UserDefaults.standard.set(false, forKey: Pref.editTip) }
        splitFraction = min(max(defaultFraction, 0.1), 0.9)
        // 미리보기를 ⌥ + 두 번 클릭하면 원본의 그 자리로 갑니다.
        session.onEditRequest = { line in
            if mode == .preview {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .split }
            }
            DispatchQueue.main.async { session.editAt(line: line) }
        }
        let binding = $document
        session.editor.onChange = { binding.wrappedValue.text = $0 }
        session.onExternalReload = { binding.wrappedValue.text = $0 }
        applyEditorSettings()
        applyPreviewSettings()
        session.preview.setFontSize(fontSize)
        session.preview.setFileURL(fileURL)
        session.textDidChange(document.text)
        session.setFile(fileURL, currentText: document.text)
        // 새 문서는 바로 쓸 수 있게 편집기를 함께 보여줍니다.
        let isNewDocument = fileURL == nil && document.text.isEmpty
        mode = isNewDocument && lastViewMode == .preview ? .split : lastViewMode
        updateLinking()
        moveFocus(for: mode)
    }

    private func applyEditorSettings() {
        let editor = session.editor
        editor.setFont(editorFont, size: fontSize)
        editor.coloring = editorColoring
        editor.autoList = autoList
        editor.autoPair = autoPair
        editor.convertRichPaste = convertRichPaste
        editor.lineNumbers = lineNumbers
        editor.showChanges = showChanges
        editor.focusMode = focusMode
        editor.typewriter = typewriter
        editor.spellCheck = spellCheck
        let folder = imageFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        editor.imageFolder = folder.isEmpty ? "images" : folder
    }

    private func applyPreviewSettings() {
        session.preview.setOptions(["font": previewFont, "width": previewWidth, "theme": previewTheme,
                                    "rich": richContent, "blockRemote": blockRemoteImages, "editTip": editTip])
    }

    private func updateLinking() {
        session.linksScrolling = syncScroll && mode == .split
    }

    /// 가려진 패널에 키보드 입력이 들어가지 않도록 보이는 쪽으로 포커스를 옮깁니다.
    private func moveFocus(for mode: ViewMode) {
        DispatchQueue.main.async {
            if mode == .preview {
                session.preview.webView.window?.makeFirstResponder(session.preview.webView)
            } else if mode == .editor || !session.editor.isFocused {
                session.editor.focus()
            }
        }
    }
}

// MARK: - 창 설정 (탭으로 열기)

private struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
    }
}

// MARK: - 다른 앱에서 바뀌었을 때

private struct ConflictBanner: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(tr("다른 앱에서 이 파일이 바뀌었어요. 이쪽에도 저장하지 않은 수정이 있어요."))
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(tr("디스크 내용 불러오기")) { session.reloadFromDisk() }
            Button(tr("내 내용 유지")) { session.keepMine() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - 사이드바 (목차 · 파일)

private struct SidebarView: View {
    @ObservedObject var session: DocumentSession
    let fileURL: URL?
    let root: URL?
    @AppStorage(Pref.sidebarTab) private var tab = "outline"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(tr("목차")).tag("outline")
                Text(tr("파일")).tag("files")
                Text(tr("검색")).tag("search")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            if tab == "files" || tab == "search" {
                if let root {
                    if tab == "files" {
                        FileTreeView(model: FolderModel.model(for: root), current: fileURL)
                            .id(root)
                    } else {
                        FolderSearchView(model: FolderModel.model(for: root))
                            .id(root)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text(tr("문서를 저장하거나 폴더를 열면\n파일 목록이 보여요."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button(tr("폴더 열기…")) { Workspace.chooseFolder() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                OutlineSidebar(session: session)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 미리보기 패널 + 찾기 막대

private struct PreviewPane: View {
    @ObservedObject var preview: PreviewController

    var body: some View {
        VStack(spacing: 0) {
            if preview.isFindVisible {
                PreviewFindBar(preview: preview)
            }
            HostedView(view: preview.webView)
        }
    }
}

private struct PreviewFindBar: View {
    @ObservedObject var preview: PreviewController
    @FocusState private var focused: Bool

    private var status: String {
        if preview.findQuery.isEmpty { return "" }
        if preview.findCount == 0 { return tr("없음") }
        return "\(preview.findIndex + 1)/\(preview.findCount)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(tr("미리보기에서 찾기"), text: $preview.findQuery)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { preview.find(step: NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                .onKeyPress(.escape) { preview.hideFind(); return .handled }
            Text(status)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(preview.findCount == 0 && !preview.findQuery.isEmpty ? .red : .secondary)
            ControlGroup {
                Button { preview.find(step: -1) } label: { Image(systemName: "chevron.left") }
                    .help(tr("이전 (⇧⌘G)"))
                Button { preview.find(step: 1) } label: { Image(systemName: "chevron.right") }
                    .help(tr("다음 (⌘G)"))
            }
            .fixedSize()
            .disabled(preview.findCount == 0)
            Button(tr("완료")) { preview.hideFind() }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: preview.findQuery) { preview.find(step: 0) }
        .onChange(of: preview.findFocusToken) { focused = true }
        .onAppear { focused = true }
    }
}

// MARK: - 목차

private struct OutlineSidebar: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        Group {
            if session.outline.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent").font(.title2).foregroundStyle(.tertiary)
                    Text(tr("제목이 없어요")).foregroundStyle(.secondary)
                    Text(tr("# 으로 시작하는 줄이 여기에 나와요."))
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let minLevel = session.outline.map(\.level).min() ?? 1
                List(selection: Binding(
                    get: { session.currentHeading },
                    set: { id in
                        if let id, let item = session.outline.first(where: { $0.id == id }) { session.jump(to: item) }
                    }
                )) {
                    ForEach(session.outline) { item in
                        Text(item.title)
                            .font(item.level == minLevel ? .body.weight(.semibold) : .body)
                            .foregroundStyle(item.level > minLevel + 1 ? .secondary : .primary)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(item.level - minLevel) * 12)
                            .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 상태 막대

private struct StatusBar: View {
    @ObservedObject var session: DocumentSession
    let mode: ViewMode
    let showChanges: Bool

    var body: some View {
        HStack(spacing: 14) {
            if mode != .preview {
                Text(tr("줄 \(session.caret.line), 열 \(session.caret.column)"))
            }
            let changes = session.changeCounts
            if showChanges, changes.added + changes.modified + changes.deleted > 0 {
                HStack(spacing: 6) {
                    if changes.added > 0 { Text("+\(changes.added)").foregroundStyle(.green) }
                    if changes.modified > 0 { Text("~\(changes.modified)").foregroundStyle(.blue) }
                    if changes.deleted > 0 { Text("−\(changes.deleted)").foregroundStyle(.red) }
                    Text(tr("(\(session.changeBaseLabel) 대비)"))
                }
                .help(tr("바뀐 줄: 추가 · 수정 · 삭제된 곳"))
            }
            if session.caret.selectedCharacters > 0 {
                Text(tr("선택: \(session.caret.selectedCharacters)자 · \(session.caret.selectedWords)단어"))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text(tr("\(session.stats.words.formatted())단어"))
            Text(tr("\(session.stats.characters.formatted())자 (공백 제외 \(session.stats.charactersNoSpaces.formatted())자)"))
            Text(tr("\(session.stats.lines.formatted())줄"))
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - 분할 화면

/// 왼쪽(원본)·오른쪽(미리보기) 패널. 가운데 구분선을 끌어 폭을 바꾸고, 끝까지 밀면 그쪽 패널이 접힙니다.
/// 두 패널 모두 항상 화면 구조에 남아 있어서 접었다 펴도 상태가 그대로입니다.
struct SplitPanes<Left: View, Right: View>: View {
    @Binding var mode: ViewMode
    @Binding var fraction: Double
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var cursorPushed = false

    private let collapseWidth: CGFloat = 140
    /// 구분선이 실제로 차지하는 폭. 편집기·미리보기 위에 겹치면 그쪽이 마우스를 가져가므로 자기 자리를 갖게 합니다.
    private let handleWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let dividerWidth: CGFloat = mode == .split ? handleWidth : 0
            let available = max(0, total - dividerWidth)
            let current = dragFraction ?? fraction
            let leftWidth: CGFloat = switch mode {
            case .editor: total
            case .preview: 0
            case .split: (available * current).rounded()
            }

            HStack(spacing: 0) {
                left
                    .frame(width: max(0, leftWidth))
                    .clipped()
                    .allowsHitTesting(mode != .preview)
                handle(available: available)
                    .frame(width: dividerWidth)
                    .opacity(mode == .split ? 1 : 0)
                    .allowsHitTesting(mode == .split)
                right
                    .frame(width: max(0, total - leftWidth - dividerWidth))
                    .clipped()
                    .allowsHitTesting(mode != .editor)
            }
            .coordinateSpace(name: "split")
            .animation(.easeInOut(duration: 0.2), value: mode)
        }
    }

    private func setCursor(_ on: Bool) {
        if on, !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
        if !on, cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    private func handle(available: CGFloat) -> some View {
        let active = hovering || dragFraction != nil
        return ZStack {
            Color(nsColor: .windowBackgroundColor)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Capsule()
                .fill(Color.secondary.opacity(active ? 0.7 : 0.35))
                .frame(width: 3, height: 32)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if dragFraction == nil { setCursor(inside) }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("split"))
                .onChanged { value in
                    guard available > 0 else { return }
                    setCursor(true)
                    let x = value.location.x - handleWidth / 2
                    dragFraction = min(max(Double(x / available), 0), 1)
                }
                .onEnded { _ in
                    guard let f = dragFraction else { return }
                    dragFraction = nil
                    if !hovering { setCursor(false) }
                    if available * f < collapseWidth {
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .preview }
                    } else if available * (1 - f) < collapseWidth {
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .editor }
                    } else {
                        fraction = f
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) { fraction = 0.5 }
        }
        .help(tr("끌어서 폭 조절 · 두 번 클릭하면 1:1"))
    }
}

/// 컨트롤러가 소유한 AppKit 뷰를 SwiftUI 레이아웃에 붙입니다.
struct HostedView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if view.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}
