import AppKit

/// 도움말 메뉴: 앱에 들어 있는 사용 설명서(마크다운)를 Mdy 로 엽니다.
/// 앱 안의 파일을 직접 고치지 않도록 사용자 폴더에 복사해서 엽니다.
@MainActor
enum Help {
    static func open() {
        let name = Loc.isEnglish ? "Help.en" : "Help"
        guard let source = Bundle.main.url(forResource: name, withExtension: "md")
                ?? Bundle.main.url(forResource: "Help", withExtension: "md") else { NSSound.beep(); return }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("Mdy", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(tr("Mdy 도움말.md"))
            let bundled = try Data(contentsOf: source)
            if (try? Data(contentsOf: target)) != bundled {
                try bundled.write(to: target, options: .atomic)
            }
            NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, error in
                if let error { NSAlert(error: error).runModal() }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
