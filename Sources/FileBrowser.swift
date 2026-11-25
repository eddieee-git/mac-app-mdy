import SwiftUI

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    var children: [FileNode]?
    var id: URL { url }
    var name: String { isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
}

/// 폴더 안의 마크다운 파일 목록. 같은 폴더를 보는 창끼리 함께 씁니다.
@MainActor
final class FolderModel: ObservableObject {
    let root: URL
    @Published private(set) var tree: [FileNode] = []
    @Published private(set) var files: [URL] = []
    @Published private(set) var isLoading = false

    private static var cache: [URL: FolderModel] = [:]
    nonisolated private static let skipped: Set<String> = ["node_modules", "Pods", "DerivedData", ".build", "build", ".git"]

    static func model(for root: URL) -> FolderModel {
        let key = root.standardizedFileURL
        if let model = cache[key] { return model }
        let model = FolderModel(root: key)
        cache[key] = model
        model.reload()
        return model
    }

    static func reloadAll() {
        cache.values.forEach { $0.reload() }
    }

    private var watcher: FolderEvents?
    private var reloadWork: DispatchWorkItem?

    private init(root: URL) {
        self.root = root
        // 폴더 안에서 파일이 생기거나 지워지면 그때만 다시 읽어요 (FSEvents).
        watcher = FolderEvents(path: root.path) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func reload() {
        isLoading = true
        let root = self.root
        Task.detached(priority: .userInitiated) {
            let result = FolderModel.scan(root)
            await MainActor.run {
                self.tree = result.tree
                self.files = result.files
                self.isLoading = false
            }
        }
    }

    nonisolated static func scan(_ root: URL) -> (tree: [FileNode], files: [URL]) {
        var files: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        func walk(_ dir: URL, depth: Int) -> [FileNode] {
            guard depth < 8, files.count < 5000,
                  let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                           options: [.skipsHiddenFiles]) else { return [] }
            var folders: [FileNode] = []
            var docs: [FileNode] = []
            for url in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    if values?.isPackage == true || skipped.contains(url.lastPathComponent) { continue }
                    let children = walk(url, depth: depth + 1)
                    if !children.isEmpty { folders.append(FileNode(url: url, isFolder: true, children: children)) }
                } else if PreviewController.markdownExtensions.contains(url.pathExtension.lowercased()) {
                    files.append(url)
                    docs.append(FileNode(url: url, isFolder: false, children: nil))
                }
            }
            return folders + docs
        }
        let tree = walk(root, depth: 0)
        return (tree, files)
    }

    /// 폴더에 새 마크다운 파일을 만들고 엽니다.
    func createFile(in folder: URL? = nil) {
        let directory = folder ?? root
        var target = directory.appendingPathComponent(tr("제목 없음.md"))
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent(tr("제목 없음 \(n).md"))
            n += 1
        }
        do {
            try Data().write(to: target)
            reload()
            Navigator.shared.open(target)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func relativePath(_ url: URL) -> String {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.lastPathComponent
    }
}

/// 사이드바에서 볼 폴더: 직접 고른 폴더가 있으면 그것, 없으면 지금 문서가 있는 폴더
enum Workspace {
    static func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("열기")
        panel.message = tr("마크다운 문서가 있는 폴더를 골라 주세요.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Pref.rootFolder)
        UserDefaults.standard.set(true, forKey: Pref.showOutline)
        UserDefaults.standard.set("files", forKey: Pref.sidebarTab)
    }

    static func root(for document: URL?) -> URL? {
        if let path = UserDefaults.standard.string(forKey: Pref.rootFolder), !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return document?.deletingLastPathComponent()
    }
}

// MARK: - 사이드바: 파일 목록

struct FileTreeView: View {
    @ObservedObject var model: FolderModel
    let current: URL?
    @AppStorage(Pref.rootFolder) private var rootFolder = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.root.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Menu {
                    Button(tr("새 문서")) { model.createFile() }
                    Button(tr("폴더 열기…")) { Workspace.chooseFolder() }
                    if !rootFolder.isEmpty {
                        Button(tr("현재 문서 폴더 보기")) { rootFolder = "" }
                    }
                    Divider()
                    Button(tr("새로 고침")) { model.reload() }
                    Button(tr("Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([model.root]) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("폴더 메뉴"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

            if model.tree.isEmpty && !model.isLoading {
                VStack(spacing: 8) {
                    Text(tr("마크다운 문서가 없어요")).foregroundStyle(.secondary)
                    Button(tr("새 문서")) { model.createFile() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.tree, children: \.children, selection: Binding(
                    get: { current?.standardizedFileURL },
                    set: { url in
                        guard let url, url != current?.standardizedFileURL,
                              !(model.tree.flatMap(Self.folders).contains(url)) else { return }
                        Navigator.shared.open(url)
                    }
                )) { node in
                    Label(node.name, systemImage: node.isFolder ? "folder" : "doc.text")
                        .lineLimit(1)
                        .tag(node.url)
                        .contextMenu {
                            if !node.isFolder { Button(tr("열기")) { Navigator.shared.open(node.url) } }
                            if node.isFolder { Button(tr("이 폴더에 새 문서")) { model.createFile(in: node.url) } }
                            Button(tr("Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                        }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private static func folders(_ node: FileNode) -> [URL] {
        node.isFolder ? [node.url] + (node.children ?? []).flatMap(folders) : []
    }
}

// MARK: - 빠른 열기 (⇧⌘O)

struct QuickOpenView: View {
    let model: FolderModel?
    @ObservedObject private var observed: FolderModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    init(model: FolderModel?) {
        self.model = model
        // 폴더가 없을 때도 뷰를 만들 수 있게 빈 모델 대신 임시 폴더를 씁니다.
        _observed = ObservedObject(wrappedValue: model ?? FolderModel.model(for: FileManager.default.temporaryDirectory))
    }

    private var results: [URL] {
        guard model != nil else { return [] }
        let files = observed.files
        if query.isEmpty { return Array(files.prefix(50)) }
        return files.compactMap { url -> (URL, Int)? in
            let name = url.deletingPathExtension().lastPathComponent
            let nameScore = Self.score(query, name).map { $0 * 2 }
            let pathScore = Self.score(query, observed.relativePath(url))
            guard let best = [nameScore, pathScore].compactMap({ $0 }).max() else { return nil }
            return (url, best)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.path.count < $1.0.path.count }
        .prefix(50)
        .map(\.0)
    }

    /// 글자들이 순서대로 들어 있으면 점수 (붙어 있거나 단어 첫 글자면 더 높게)
    static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }
        var qi = 0, score = 0, last = -2
        for (i, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            score += i == last + 1 ? 5 : 1
            if i == 0 || "/-_ .".contains(c[i - 1]) { score += 3 }
            last = i
            qi += 1
        }
        return qi == q.count ? score : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("파일 이름으로 찾기"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(openSelected)
                    .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, results.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(12)
            Divider()
            if model == nil {
                VStack(spacing: 10) {
                    Text(tr("먼저 폴더를 열어 주세요")).foregroundStyle(.secondary)
                    Button(tr("폴더 열기…")) { dismiss(); Workspace.chooseFolder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, url in
                                HStack {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.deletingPathExtension().lastPathComponent).lineLimit(1)
                                        Text(observed.relativePath(url)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(index == selected ? Color.accentColor.opacity(0.2) : .clear)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = index; openSelected() }
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: selected) { _, value in proxy.scrollTo(value) }
                }
                if results.isEmpty {
                    Text(observed.isLoading ? tr("찾는 중…") : tr("맞는 문서가 없어요")).foregroundStyle(.secondary).padding()
                }
            }
            Divider()
            Text(tr("↑↓ 고르기 · ↩ 열기 · esc 닫기")).font(.caption).foregroundStyle(.secondary).padding(6)
        }
        .frame(width: 520, height: 420)
        .onAppear { focused = true; observed.reload() }
        .onChange(of: query) { selected = 0 }
    }

    private func openSelected() {
        let list = results
        guard selected < list.count else { return }
        dismiss()
        Navigator.shared.open(list[selected])
    }
}

/// 폴더 아래(하위 폴더 포함)의 변화를 알려 주는 FSEvents 감시
final class FolderEvents {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderEvents>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                               UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

// MARK: - 사이드바: 폴더 안 내용 검색 (⇧⌘F)

struct SearchHit: Identifiable, Hashable {
    let url: URL
    let line: Int
    let text: String
    var id: String { url.path + "#\(line)" }
}

@MainActor
final class FolderSearch: ObservableObject {
    static let shared = FolderSearch()
    @Published var query = ""
    @Published private(set) var results: [(url: URL, hits: [SearchHit])] = []
    @Published private(set) var isSearching = false
    @Published private(set) var truncated = false
    @Published var focusToken = 0
    private var task: Task<Void, Never>?

    private func apply(_ found: [(URL, [SearchHit])], truncated: Bool) {
        results = found.map { (url: $0.0, hits: $0.1) }
        self.truncated = truncated
        isSearching = false
    }

    func search(in model: FolderModel) {
        task?.cancel()
        let query = self.query.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { results = []; isSearching = false; return }
        let files = model.files
        isSearching = true
        task = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            var found: [(URL, [SearchHit])] = []
            var total = 0
            let limit = 1000
            for url in files {
                if Task.isCancelled { return }
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      (values.fileSize ?? 0) < 4_000_000, let data = try? Data(contentsOf: url) else { continue }
                let text = MarkdownDocument.decode(data)
                guard text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                var hits: [SearchHit] = []
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    hits.append(SearchHit(url: url, line: index, text: String(line.prefix(300)).trimmingCharacters(in: .whitespaces)))
                    total += 1
                    if total >= limit { break }
                }
                found.append((url, hits))
                if total >= limit { break }
            }
            let result = found
            let cut = total >= limit
            if Task.isCancelled { return }
            await self?.apply(result, truncated: cut)
        }
    }
}

struct FolderSearchView: View {
    @ObservedObject var model: FolderModel
    @ObservedObject private var search = FolderSearch.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("폴더에서 찾기"), text: $search.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { search.search(in: model) }
                if search.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            Divider()
            if search.query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text(tr("두 글자 이상 쓰면 \(model.root.lastPathComponent) 폴더의 모든 문서에서 찾아요."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if search.results.isEmpty && !search.isSearching {
                Text(tr("찾은 곳이 없어요")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(search.results, id: \.url) { group in
                        Section {
                            ForEach(group.hits) { hit in
                                Button {
                                    Navigator.shared.open(hit.url, line: hit.line, query: search.query)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(hit.line + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                            .frame(minWidth: 24, alignment: .trailing)
                                        Text(highlighted(hit.text)).lineLimit(2)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(model.relativePath(group.url)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    if search.truncated {
                        Text(tr("결과가 많아 1000곳까지만 보여요")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: search.query) { search.search(in: model) }
        .onChange(of: search.focusToken) { focused = true }
        .onAppear { focused = true; if !search.query.isEmpty { search.search(in: model) } }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        var searchStart = result.startIndex
        while let range = result[searchStart...].range(of: search.query, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].backgroundColor = .yellow.opacity(0.45)
            searchStart = range.upperBound
        }
        return result
    }
}
