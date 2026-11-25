import ServiceManagement
import SwiftUI

/// 설정 키 (UserDefaults). 여러 화면이 같은 값을 읽으므로 한곳에 모아 둬요.
enum Pref {
    static let fontSize = "fontSize"
    static let editorFont = "editorFont"
    static let editorColoring = "editorColoring"
    static let autoList = "autoList"
    static let imageFolder = "imageFolder"
    static let previewFont = "previewFont"
    static let previewWidth = "previewWidth"
    static let previewTheme = "previewTheme"
    static let richContent = "richContent"
    static let appearance = "appearance"
    static let syncScroll = "syncScroll"
    static let lastViewMode = "lastViewMode"
    static let showOutline = "showOutline"
    static let showStatusBar = "showStatusBar"
    static let sidebarTab = "sidebarTab"
    static let rootFolder = "rootFolder"
    static let autoPair = "autoPair"
    static let convertRichPaste = "convertRichPaste"
    static let lineNumbers = "lineNumbers"
    static let showChanges = "showChanges"
    static let focusMode = "focusMode"
    static let typewriter = "typewriter"
    static let openInTabs = "openInTabs"
    static let showWelcome = "showWelcome"
    static let editTip = "editTip"
    static let spellCheck = "spellCheck"
    static let blockRemoteImages = "blockRemoteImages"
}

enum EditorFont: String, CaseIterable, Identifiable {
    case mono, menlo, system
    var id: Self { self }
    var title: String {
        switch self {
        case .mono: tr("SF Mono (고정폭)")
        case .menlo: tr("Menlo (고정폭)")
        case .system: tr("시스템 글꼴 (비례폭)")
        }
    }
    func font(size: CGFloat) -> NSFont {
        switch self {
        case .mono: .monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo: NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .system: .systemFont(ofSize: size)
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: tr("시스템 설정 따르기")
        case .light: tr("밝게")
        case .dark: tr("어둡게")
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label(tr("일반"), systemImage: "gearshape") }
            EditorSettings().tabItem { Label(tr("편집기"), systemImage: "square.and.pencil") }
            PreviewSettings().tabItem { Label(tr("미리보기"), systemImage: "eye") }
            AboutSettings().tabItem { Label(tr("정보"), systemImage: "info.circle") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Pref.appearance) private var appearance: AppAppearance = .system
    @AppStorage(Pref.lastViewMode) private var viewMode: ViewMode = .split
    @AppStorage(Pref.syncScroll) private var syncScroll = true
    @AppStorage(Pref.showOutline) private var showOutline = false
    @AppStorage(Pref.showStatusBar) private var showStatusBar = true
    @AppStorage(Pref.openInTabs) private var openInTabs = true
    @AppStorage(Pref.showWelcome) private var showWelcome = true
    @AppStorage(Pref.rootFolder) private var rootFolder = ""
    @AppStorage(Loc.languageKey) private var language = "system"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker(tr("화면 모드"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: appearance) { _, value in value.apply() }
                Picker(tr("문서를 열 때 보기"), selection: $viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle(tr("스크롤 동기화"), isOn: $syncScroll)
                Toggle(tr("사이드바 보기"), isOn: $showOutline)
                Toggle(tr("상태 막대 보기"), isOn: $showStatusBar)
                Toggle(tr("문서를 한 창의 탭으로 열기"), isOn: $openInTabs)
                Toggle(tr("문서 없이 열면 시작 창 보기"), isOn: $showWelcome)
                LabeledContent(tr("작업 폴더")) {
                    HStack {
                        Text(rootFolder.isEmpty ? tr("지금 문서가 있는 폴더") : (rootFolder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button(tr("바꾸기…")) { Workspace.chooseFolder() }
                        if !rootFolder.isEmpty { Button(tr("지우기")) { rootFolder = "" } }
                    }
                }
            }

            Section {
                Toggle(tr("로그인 시 실행"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker(tr("언어"), selection: $language) {
                    Text(tr("시스템")).tag("system")
                    Text("한국어").tag("ko") // no-tr
                    Text("English").tag("en")
                }
                Text(tr("언어를 바꾸면 Mdy를 다시 열어야 적용돼요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AppUpdaterSection(updater: .shared)
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @AppStorage(Pref.editorFont) private var editorFont: EditorFont = .mono
    @AppStorage(Pref.fontSize) private var fontSize: Double = Zoom.defaultSize
    @AppStorage(Pref.editorColoring) private var coloring = true
    @AppStorage(Pref.autoList) private var autoList = true
    @AppStorage(Pref.imageFolder) private var imageFolder = "images"
    @AppStorage(Pref.autoPair) private var autoPair = true
    @AppStorage(Pref.convertRichPaste) private var convertRichPaste = true
    @AppStorage(Pref.lineNumbers) private var lineNumbers = false
    @AppStorage(Pref.showChanges) private var showChanges = true
    @AppStorage(Pref.spellCheck) private var spellCheck = false

    var body: some View {
        Form {
            Picker(tr("글꼴"), selection: $editorFont) {
                ForEach(EditorFont.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent(tr("글자 크기")) {
                HStack {
                    Slider(value: $fontSize, in: Zoom.range, step: 1)
                    Text("\(Int(fontSize))pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            Toggle(tr("마크다운 문법 색칠"), isOn: $coloring)
            Toggle(tr("맞춤법 검사"), isOn: $spellCheck)
            Toggle(tr("목록·인용·표 자동 이어쓰기 (Tab으로 들여쓰기·칸 이동)"), isOn: $autoList)
            Toggle(tr("괄호·기호 짝 맞추기"), isOn: $autoPair)
            Toggle(isOn: $convertRichPaste) {
                Text(tr("서식 있는 글을 붙여 넣으면 마크다운으로 바꾸기"))
                Text(tr("서식 없이 붙이려면 ⌥⇧⌘V"))
            }
            Toggle(tr("줄 번호"), isOn: $lineNumbers)
            Toggle(isOn: $showChanges) {
                Text(tr("바뀐 줄 표시"))
                Text(tr("git 저장소의 문서는 마지막 커밋, 아니면 문서를 연 때와 비교해요."))
            }
            TextField(tr("붙여 넣은 이미지 저장 폴더"), text: $imageFolder)
                .help(tr("문서와 같은 위치 기준의 폴더 이름이에요."))
        }
        .formStyle(.grouped)
    }
}

private struct PreviewSettings: View {
    @AppStorage(Pref.previewFont) private var previewFont = "sans"
    @AppStorage(Pref.previewWidth) private var previewWidth = "normal"
    @AppStorage(Pref.previewTheme) private var previewTheme = "github"
    @AppStorage(Pref.richContent) private var richContent = true
    @AppStorage(Pref.blockRemoteImages) private var blockRemoteImages = false
    @AppStorage(Pref.editTip) private var editTip = true

    var body: some View {
        Form {
            Picker(tr("글꼴"), selection: $previewFont) {
                Text(tr("고딕 (산세리프)")).tag("sans")
                Text(tr("명조 (세리프)")).tag("serif")
            }
            Picker(tr("본문 폭"), selection: $previewWidth) {
                Text(tr("좁게")).tag("narrow")
                Text(tr("보통")).tag("normal")
                Text(tr("넓게")).tag("wide")
                Text(tr("창 전체")).tag("full")
            }
            Picker(tr("테마"), selection: $previewTheme) {
                Text("GitHub").tag("github")
                Text(tr("종이")).tag("paper")
            }
            Toggle(isOn: $richContent) {
                Text(tr("수식·다이어그램 그리기"))
                Text(PreviewController.bundledLibraries.count == 2
                     ? tr("KaTeX·Mermaid가 앱에 들어 있어 인터넷 없이 그려요.")
                     : tr("문서에 수식이나 mermaid 블록이 있을 때 KaTeX·Mermaid를 인터넷(jsDelivr)에서 불러와요."))
            }
            Toggle(isOn: $blockRemoteImages) {
                Text(tr("외부 이미지 막기"))
                Text(tr("인터넷 주소의 이미지를 바로 불러오지 않아요. 받은 문서를 열었다는 사실이 상대에게 알려지지 않게 해 줘요. 문서마다 위쪽의 불러오기로 볼 수 있어요."))
            }
            Toggle(tr("“두 번 클릭해서 고치기” 안내 보기"), isOn: $editTip)
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        Form {
            AppAboutSections(appName: "Mdy", english: Loc.isEnglish)
        }
        .formStyle(.grouped)
    }
}
