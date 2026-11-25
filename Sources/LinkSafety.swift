import AppKit
import UniformTypeIdentifiers

/// 미리보기에서 누른 링크를 열어도 되는지 정해요.
/// 받은 문서 안의 링크로 프로그램이 실행되지 않게, 실행 파일은 열지 않고 낯선 주소는 먼저 물어봐요.
@MainActor
enum LinkSafety {
    /// 바로 열어도 되는 주소
    private static let safeSchemes: Set<String> = ["http", "https", "mailto"]

    /// 열면 무언가가 실행되는 파일
    private static let executableExtensions: Set<String> = [
        "app", "command", "tool", "sh", "bash", "zsh", "csh", "ksh", "fish", "py", "pl", "rb", "php", "js",
        "jar", "pkg", "mpkg", "dmg", "scpt", "scptd", "applescript", "workflow", "action", "terminal",
        "prefpane", "kext", "plugin", "bundle", "dylib", "so", "exe", "bat", "msi", "inetloc", "webloc", "fileloc",
        "shortcut", "mobileconfig", "osax", "qlgenerator", "appex", "xpc", "service",
    ]

    enum Decision { case open, ask(String), block(String) }

    static func decide(_ url: URL) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if safeSchemes.contains(scheme) { return .open }
        if url.isFileURL { return decideFile(url) }
        return .ask(tr("이 링크는 다른 앱을 열어요."))
    }

    private static func decideFile(_ url: URL) -> Decision {
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .block(tr("파일을 찾을 수 없어요."))
        }
        let ext = url.pathExtension.lowercased()
        if executableExtensions.contains(ext) { return .block(tr("실행할 수 있는 파일이라 열지 않았어요.")) }
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .executable) || type.conforms(to: .application) || type.conforms(to: .script) ||
           type.conforms(to: .applicationBundle) || type.identifier == "com.apple.installer-package-archive" {
            return .block(tr("실행할 수 있는 파일이라 열지 않았어요."))
        }
        if isDirectory.boolValue {
            // 폴더는 Finder 로 보여 주기만 해요 (번들 안으로 들어가 실행되지 않게).
            return .open
        }
        // 확장자 없이 실행 권한만 있는 파일 (스크립트·프로그램)
        if ext.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return .block(tr("실행할 수 있는 파일이라 열지 않았어요."))
        }
        return .open
    }

    /// 링크를 결정에 따라 열어요. 막거나 물을 때는 창을 띄워요.
    static func open(_ url: URL, in window: NSWindow?) {
        switch decide(url) {
        case .open:
            var isDirectory: ObjCBool = false
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else if !NSWorkspace.shared.open(url) {
                NSSound.beep()
            }
        case .ask(let reason):
            let alert = NSAlert()
            alert.messageText = tr("링크를 열까요?")
            alert.informativeText = reason + "\n\n" + url.absoluteString
            alert.addButton(withTitle: tr("열기"))
            alert.addButton(withTitle: tr("취소"))
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
            }
            if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
        case .block(let reason):
            let alert = NSAlert()
            alert.messageText = tr("링크를 열지 않았어요")
            alert.informativeText = reason + "\n\n" + url.path
            alert.addButton(withTitle: tr("확인"))
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                alert.addButton(withTitle: tr("Finder에서 보기"))
            }
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertSecondButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
        }
    }
}
