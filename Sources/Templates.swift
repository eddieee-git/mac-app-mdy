import AppKit
import SwiftUI

/// 문서 템플릿: ~/Library/Application Support/Mdy/Templates 의 .md 파일들.
/// 처음 쓸 때 앱에 들어 있는 기본 템플릿(회의록·일지…)을 복사해 둬요.
/// 템플릿 안의 {{날짜}} {{시간}} {{요일}} ({{date}} {{time}} {{weekday}}) 는 새 문서를 만들 때 바뀌어요.
@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    @Published private(set) var templates: [URL] = []

    let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Mdy/Templates", isDirectory: true)
    }()

    private init() {
        installDefaultsIfNeeded()
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        templates = files
            .filter { PreviewController.markdownExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func installDefaultsIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let language = Loc.isEnglish ? "en" : "ko"
        guard let source = Bundle.main.url(forResource: language, withExtension: nil, subdirectory: "Templates"),
              let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent)) }
    }

    static func name(of url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    /// 템플릿으로 제목 없는 새 문서를 만들어요 (저장하면 그때 위치를 정해요).
    func newDocument(from template: URL) {
        guard let data = try? Data(contentsOf: template) else { NSSound.beep(); return }
        var text = MarkdownDocument.decode(data)
        let now = Date()
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: Loc.isEnglish ? "en_US" : "ko_KR")
            f.dateFormat = pattern
            return f.string(from: now)
        }
        for (keys, value) in [(["{{날짜}}", "{{date}}"], format("yyyy-MM-dd")), // no-tr
                              (["{{시간}}", "{{time}}"], format("HH:mm")), // no-tr
                              (["{{요일}}", "{{weekday}}"], format("EEEE"))] { // no-tr
            for key in keys { text = text.replacingOccurrences(of: key, with: value) }
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = temp.appendingPathComponent(template.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            _ = try NSDocumentController.shared.duplicateDocument(withContentsOf: file, copying: true,
                                                                  displayName: Self.name(of: template))
            try? FileManager.default.removeItem(at: temp)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// 지금 문서를 템플릿으로 저장해요. 이름은 물어봐요.
    func save(text: String, suggestedName: String) {
        let alert = NSAlert()
        alert.messageText = tr("템플릿으로 저장")
        alert.informativeText = tr("새 문서를 만들 때 고를 이름이에요. {{날짜}} {{시간}} {{요일}}은 만들 때 바뀌어요.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = suggestedName
        alert.accessoryView = field
        alert.addButton(withTitle: tr("저장"))
        alert.addButton(withTitle: tr("취소"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty else { NSSound.beep(); return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: folder.appendingPathComponent(name + ".md"), options: .atomic)
            reload()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
