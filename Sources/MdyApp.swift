import SwiftUI

@main
struct MdyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.migrateOldSettings()
        // 설정 → 언어를 고르면 macOS 가 만드는 메뉴(파일·편집…)도 같은 언어로
        switch UserDefaults.standard.string(forKey: Loc.languageKey) ?? "system" {
        case "ko": UserDefaults.standard.set(["ko"], forKey: "AppleLanguages")
        case "en": UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        default: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.register(defaults: [
            Pref.editorColoring: true,
            Pref.autoList: true,
            Pref.richContent: true,
            Pref.syncScroll: true,
            Pref.showStatusBar: true,
            Pref.imageFolder: "images",
            Pref.autoPair: true,
            Pref.convertRichPaste: true,
            Pref.showChanges: true,
            Pref.openInTabs: true,
            Pref.showWelcome: true,
            Pref.editTip: true,
            // 문서 없이 열었을 때 macOS 의 열기 창 대신 Mdy 시작 창을 보여 줘요.
            "NSShowAppCentricOpenPanelInsteadOfUntitledFile": false,
        ])
    }

    /// 번들 ID 를 app.mdy.Mdy → com.eddieee.Mdy 로 바꿔서, 예전 설정을 한 번 옮겨 와요 (새로 정한 값은 그대로).
    private static func migrateOldSettings() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromAppMdy"),
              let old = UserDefaults(suiteName: "app.mdy.Mdy")?.persistentDomain(forName: "app.mdy.Mdy") else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil && !key.hasPrefix("NS") {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: "migratedFromAppMdy")
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            UpdateCommands()
            MdyCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

/// 시작 창, 업데이트, Dock 아이콘 오른쪽 클릭 메뉴
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdater.shared.start()
        // SwiftUI 문서 앱은 문서 없이 열리면 빈 "제목 없음" 문서를 저절로 만들어요.
        // 그 빈 문서 하나뿐이면 닫고 시작 창을 보여 줘요 (파일을 더블클릭해 열었을 때는 그대로).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { Self.replaceEmptyUntitledWithWelcome() } }
    }

    @MainActor
    static func replaceEmptyUntitledWithWelcome() {
        guard UserDefaults.standard.bool(forKey: Pref.showWelcome) else { return }
        let documents = NSDocumentController.shared.documents
        if documents.isEmpty {
            WelcomeWindow.show()
            return
        }
        guard documents.count == 1, let only = documents.first, only.fileURL == nil, !only.isDocumentEdited else { return }
        only.close()
        WelcomeWindow.show()
    }

    /// Dock 아이콘을 눌렀는데 열린 창이 없을 때도 시작 창
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, UserDefaults.standard.bool(forKey: Pref.showWelcome) else { return true }
        MainActor.assumeIsolated { WelcomeWindow.show() }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("새 문서"), action: #selector(newDocument), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("열기…"), action: #selector(openDocument), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("시작 창"), action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Mdy 도움말"), action: #selector(openHelp), keyEquivalent: "").target = self
        return menu
    }

    @MainActor @objc private func newDocument() {
        NSApp.activate()
        NSDocumentController.shared.newDocument(nil)
    }

    @MainActor @objc private func openDocument() {
        NSApp.activate()
        NSDocumentController.shared.openDocument(nil)
    }

    @MainActor @objc private func showWelcome() {
        WelcomeWindow.show()
    }

    @MainActor @objc private func openHelp() {
        NSApp.activate()
        Help.open()
    }
}
