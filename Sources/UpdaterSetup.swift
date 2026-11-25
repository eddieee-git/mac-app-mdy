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

/// 설정의 "정보". Mdy 는 아직 공통 앱 목록(AppFamily)에 없어서 자기 정보는 여기서 보여 주고,
/// 다른 앱 목록만 공통 것을 써요.
struct MdyAboutSections: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }
    private let repo = URL(string: "https://github.com/\(AppFamily.owner)/mac-app-mdy")!

    var body: some View {
        Section(tr("정보")) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mdy").font(.headline)
                    Text(tr("버전 \(version)")).foregroundStyle(.secondary)
                    Text(tr("더블클릭으로 바로 여는 마크다운 뷰어 겸 편집기")).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Link("GitHub", destination: repo)
                Link(tr("변경 기록"), destination: repo.appendingPathComponent("releases"))
                Link(tr("문제 알리기"), destination: repo.appendingPathComponent("issues/new/choose"))
            }
            .font(.callout)
        }
        Section(tr("다른 앱")) {
            ForEach(AppFamily.members) { app in
                Link(destination: app.url) {
                    HStack {
                        Text(app.name).fontWeight(.medium)
                        Text(Loc.isEnglish ? app.en : app.ko).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(app.name), \(Loc.isEnglish ? app.en : app.ko)")
            }
        }
    }
}
