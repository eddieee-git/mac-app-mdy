import AppKit
import SwiftUI

/// 공통 업데이트(AppUpdater.swift)에 Mdy 정보를 넣어요. AppUpdater.swift 는 mac-app/shared 에서 복사해 오므로 여기만 고쳐요.
extension AppUpdater {
    /// 업데이트 서명 공개 키. Info.plist 의 MdyUpdatePublicKey (build.sh dist 가 같은 값으로 확인해요).
    nonisolated static let appPublicKey = Bundle.main.object(forInfoDictionaryKey: "MdyUpdatePublicKey") as? String ?? ""
    nonisolated static let appSignatureFormat = SignatureFormat.dmg

    static let shared = AppUpdater(.init(
        appName: "Mdy",
        repo: "eddieee-git/mac-app-mdy",
        publicKey: appPublicKey,
        signatureFormat: appSignatureFormat,
        isEnglish: { Loc.isEnglish }
    ))
}

/// Mdy 메뉴의 "업데이트 확인…" / "새 버전 X 설치…"
struct UpdateCommands: Commands {
    @ObservedObject var updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(updater.menuTitle) { updater.menuAction() }
                .disabled(updater.isBusy)
        }
    }
}
