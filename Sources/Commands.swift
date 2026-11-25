import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case editor, split, preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editor: tr("원본만")
        case .split: tr("원본과 미리보기 나란히")
        case .preview: tr("미리보기만")
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .editor: "1"
        case .split: "2"
        case .preview: "3"
        }
    }
}

/// 원본 : 미리보기 폭 비율
enum SplitPreset: CaseIterable, Identifiable {
    case editorNarrow, even, editorWide

    var id: Self { self }
    var fraction: Double {
        switch self {
        case .editorNarrow: 0.25
        case .even: 0.5
        case .editorWide: 0.75
        }
    }
    var title: String {
        switch self {
        case .editorNarrow: tr("1 : 3 (미리보기 넓게)")
        case .even: "1 : 1"
        case .editorWide: tr("3 : 1 (원본 넓게)")
        }
    }
    var symbol: String {
        switch self {
        case .editorNarrow: "rectangle.leftthird.inset.filled"
        case .even: "rectangle.split.2x1"
        case .editorWide: "rectangle.rightthird.inset.filled"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .editorNarrow: "1"
        case .even: "2"
        case .editorWide: "3"
        }
    }

    static func matching(_ fraction: Double) -> SplitPreset? {
        allCases.first { abs($0.fraction - fraction) < 0.02 }
    }
}

enum Zoom {
    static let defaultSize: Double = 14
    static let range: ClosedRange<Double> = 9...36
}

struct ViewModeKey: FocusedValueKey { typealias Value = Binding<ViewMode> }
struct PreviewKey: FocusedValueKey { typealias Value = PreviewController }
struct EditorKey: FocusedValueKey { typealias Value = EditorController }
struct SplitFractionKey: FocusedValueKey { typealias Value = Binding<Double> }
struct SessionKey: FocusedValueKey { typealias Value = DocumentSession }
struct QuickOpenKey: FocusedValueKey { typealias Value = Binding<Bool> }

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
    var preview: PreviewController? {
        get { self[PreviewKey.self] }
        set { self[PreviewKey.self] = newValue }
    }
    var editor: EditorController? {
        get { self[EditorKey.self] }
        set { self[EditorKey.self] = newValue }
    }
    var splitFraction: Binding<Double>? {
        get { self[SplitFractionKey.self] }
        set { self[SplitFractionKey.self] = newValue }
    }
    var session: DocumentSession? {
        get { self[SessionKey.self] }
        set { self[SessionKey.self] = newValue }
    }
    var quickOpen: Binding<Bool>? {
        get { self[QuickOpenKey.self] }
        set { self[QuickOpenKey.self] = newValue }
    }
}

struct MdyCommands: Commands {
    @FocusedValue(\.viewMode) private var viewMode
    @FocusedValue(\.preview) private var preview
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.splitFraction) private var splitFraction
    @FocusedValue(\.session) private var session
    @FocusedValue(\.quickOpen) private var quickOpen
    @ObservedObject private var templates = TemplateStore.shared
    @AppStorage(Pref.lineNumbers) private var lineNumbers = false
    @AppStorage(Pref.showChanges) private var showChanges = true
    @AppStorage(Pref.focusMode) private var focusMode = false
    @AppStorage(Pref.typewriter) private var typewriter = false
    @AppStorage(Pref.fontSize) private var fontSize: Double = Zoom.defaultSize
    @AppStorage(Pref.syncScroll) private var syncScroll = true
    @AppStorage(Pref.showOutline) private var showOutline = false
    @AppStorage(Pref.showStatusBar) private var showStatusBar = true

    private var editorHidden: Bool { editor == nil || viewMode?.wrappedValue == .preview }
    private var previewHidden: Bool { preview == nil || viewMode?.wrappedValue == .editor }

    var body: some Commands {
        // 파일 > 빠른 열기 · 폴더 열기
        CommandGroup(after: .newItem) {
            Button(tr("빠른 열기…")) { quickOpen?.wrappedValue = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(quickOpen == nil)
            Button(tr("폴더 열기…")) { Workspace.chooseFolder() }
            Menu(tr("템플릿으로 새 문서")) {
                ForEach(templates.templates, id: \.self) { url in
                    Button(TemplateStore.name(of: url)) { templates.newDocument(from: url) }
                }
                Divider()
                Button(tr("이 문서를 템플릿으로 저장…")) {
                    guard let session else { return }
                    templates.save(text: session.editor.textView.string,
                                   suggestedName: session.fileURL?.deletingPathExtension().lastPathComponent ?? tr("새 템플릿"))
                }
                .disabled(session == nil)
                Button(tr("템플릿 폴더 열기")) { templates.revealFolder() }
            }
        }

        // 편집 > 서식 있는 텍스트로 복사
        CommandGroup(after: .pasteboard) {
            Button(tr("서식 있는 텍스트로 복사")) { session?.copyRich() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(session == nil)
        }

        // 이동
        CommandMenu(tr("이동")) {
            Button(tr("뒤로")) { Navigator.shared.goBack(from: session?.fileURL) }
                .keyboardShortcut("[", modifiers: .command)
            Button(tr("앞으로")) { Navigator.shared.goForward(from: session?.fileURL) }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button(tr("빠른 열기…")) { quickOpen?.wrappedValue = true }
                .disabled(quickOpen == nil)
            Button(tr("폴더에서 찾기…")) {
                UserDefaults.standard.set(true, forKey: Pref.showOutline)
                UserDefaults.standard.set("search", forKey: Pref.sidebarTab)
                FolderSearch.shared.focusToken += 1
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button(tr("시작 창")) { WelcomeWindow.show() }
        }

        // 파일 > 내보내기
        CommandGroup(replacing: .importExport) {
            Button(tr("HTML로 내보내기…")) { preview?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(preview == nil)
            Button(tr("PDF로 내보내기…")) { preview?.exportPDF() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(previewHidden)
            Button(tr("Word로 내보내기…")) { preview?.exportOffice(.word) }
                .disabled(preview == nil)
            Button(tr("RTF로 내보내기…")) { preview?.exportOffice(.rtf) }
                .disabled(preview == nil)
        }

        // 파일 > 프린트
        CommandGroup(replacing: .printItem) {
            Button(tr("프린트…")) { preview?.printDocument() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(previewHidden)
        }

        // 보기 메뉴
        CommandGroup(before: .toolbar) {
            ForEach(ViewMode.allCases) { mode in
                Button(tr("\(mode.title) 보기")) {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode?.wrappedValue = mode }
                }
                .keyboardShortcut(mode.shortcut, modifiers: .command)
                .disabled(viewMode == nil)
            }
            Menu(tr("원본 : 미리보기 비율")) {
                ForEach(SplitPreset.allCases) { preset in
                    Button(preset.title) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode?.wrappedValue = .split
                            splitFraction?.wrappedValue = preset.fraction
                        }
                    }
                    .keyboardShortcut(preset.shortcut, modifiers: [.command, .option])
                }
            }
            .disabled(splitFraction == nil)
            Divider()
            Toggle(tr("사이드바 (목차·파일)"), isOn: $showOutline)
                .keyboardShortcut("s", modifiers: [.command, .control])
            Toggle(tr("상태 막대"), isOn: $showStatusBar)
                .keyboardShortcut("/", modifiers: .command)
            Toggle(tr("스크롤 동기화"), isOn: $syncScroll)
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Toggle(tr("줄 번호"), isOn: $lineNumbers)
            Toggle(tr("바뀐 줄 표시"), isOn: $showChanges)
            Toggle(tr("집중 모드"), isOn: $focusMode)
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Toggle(tr("타자기 스크롤"), isOn: $typewriter)
            Menu(tr("제목 접기")) {
                Button(tr("이 제목 접기")) { editor?.foldCurrent() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button(tr("이 제목 펴기")) { editor?.unfoldCurrent() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Divider()
                Button(tr("모두 접기")) { editor?.foldAll() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .control])
                Button(tr("모두 펴기")) { editor?.unfoldAll() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .control])
            }
            .disabled(editorHidden)
            Divider()
            Button(tr("실제 크기")) { fontSize = Zoom.defaultSize }
                .keyboardShortcut("0", modifiers: .command)
            Button(tr("확대")) { fontSize = min(fontSize + 1, Zoom.range.upperBound) }
                .keyboardShortcut("=", modifiers: .command)
            Button(tr("축소")) { fontSize = max(fontSize - 1, Zoom.range.lowerBound) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
        }

        // 서식 메뉴
        CommandMenu(tr("서식")) {
            Group {
                Button(tr("굵게")) { editor?.toggleWrap("**") }
                    .keyboardShortcut("b", modifiers: .command)
                Button(tr("기울임")) { editor?.toggleWrap("*") }
                    .keyboardShortcut("i", modifiers: .command)
                Button(tr("취소선")) { editor?.toggleWrap("~~") }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button(tr("형광펜")) { editor?.toggleWrap("==") }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button(tr("코드")) { editor?.toggleWrap("`") }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button(tr("링크")) { editor?.insertLink() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Menu(tr("표")) {
                    Button(tr("표 넣기")) { editor?.insertTable() }
                    Button(tr("표 정렬")) { editor?.formatTable() }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                    Divider()
                    Button(tr("아래에 행 추가")) { editor?.addTableRow() }
                    Button(tr("오른쪽에 열 추가")) { editor?.addTableColumn() }
                    Divider()
                    Button(tr("행 삭제")) { editor?.deleteTableRow() }
                    Button(tr("열 삭제")) { editor?.deleteTableColumn() }
                }
                Menu(tr("제목")) {
                    ForEach(1...6, id: \.self) { level in
                        Button(tr("제목 \(level)")) { editor?.setHeading(level) }
                            .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.command, .control])
                    }
                    Divider()
                    Button(tr("본문")) { editor?.setHeading(0) }
                        .keyboardShortcut("0", modifiers: [.command, .control])
                }
            }
            .disabled(editorHidden)
        }

        // 도움말
        CommandGroup(replacing: .help) {
            Button(tr("Mdy 도움말")) { Help.open() }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
