import AppKit
import SwiftUI

/// 문서 없이 Mdy 를 열었을 때 보이는 시작 창: 새 문서 · 열기 · 폴더 열기 · 최근 문서 · 템플릿
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let hosting = NSHostingController(rootView: WelcomeView())
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Mdy 시작")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    static func close() {
        window?.close()
    }

    static var isVisible: Bool { window?.isVisible ?? false }
}

private struct WelcomeView: View {
    @ObservedObject private var templates = TemplateStore.shared
    @AppStorage(Pref.showWelcome) private var showWelcome = true
    @State private var recents: [URL] = NSDocumentController.shared.recentDocumentURLs

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Mdy").font(.largeTitle.weight(.semibold))
                Text(tr("버전 \(version)")).font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    action(tr("새 문서"), "doc.badge.plus", "⌘N") { NSDocumentController.shared.newDocument(nil) }
                    action(tr("열기…"), "folder", "⌘O") { NSDocumentController.shared.openDocument(nil) }
                    action(tr("폴더 열기…"), "folder.badge.gearshape", "") {
                        Workspace.chooseFolder()
                        if let path = UserDefaults.standard.string(forKey: Pref.rootFolder), !path.isEmpty {
                            NSDocumentController.shared.newDocument(nil)
                        }
                    }
                    action(tr("도움말"), "questionmark.circle", "⌘?") { Help.open() }
                }
                .padding(.top, 8)
                Spacer()
                Toggle(tr("Mdy를 열 때 이 창 보기"), isOn: $showWelcome)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(28)
            .frame(width: 280)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                section(tr("최근 문서"))
                if recents.isEmpty {
                    Text(tr("아직 연 문서가 없어요")).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
                } else {
                    ForEach(recents.prefix(8), id: \.self) { url in
                        row(title: url.deletingPathExtension().lastPathComponent,
                            subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                            icon: "doc.text") {
                            Navigator.shared.open(url)
                            WelcomeWindow.close()
                        }
                    }
                }
                section(tr("템플릿으로 새 문서")).padding(.top, 10)
                ForEach(templates.templates, id: \.self) { url in
                    row(title: TemplateStore.name(of: url), subtitle: nil, icon: "doc.on.doc") {
                        templates.newDocument(from: url)
                        WelcomeWindow.close()
                    }
                }
                Button(tr("템플릿 폴더 열기")) { templates.revealFolder() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                Spacer()
            }
            .padding(.vertical, 20)
            .frame(width: 380)
        }
        .frame(height: 440)
        .onAppear {
            recents = NSDocumentController.shared.recentDocumentURLs
            templates.reload()
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.bottom, 4)
    }

    private func action(_ title: String, _ icon: String, _ key: String, _ perform: @escaping () -> Void) -> some View {
        Button {
            perform()
            WelcomeWindow.close()
        } label: {
            HStack {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
                Text(key).foregroundStyle(.tertiary).font(.callout)
            }
            .frame(width: 200)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    private func row(title: String, subtitle: String?, icon: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
