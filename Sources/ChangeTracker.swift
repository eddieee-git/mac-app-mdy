import Foundation

/// 기준 내용(git 의 마지막 커밋, 또는 문서를 연 때)과 비교한 줄 변경 표시
struct ChangeMarkers: Equatable {
    enum Kind { case added, modified }
    var lines: [Int: Kind] = [:]
    /// 이 줄 앞에서 줄이 지워졌음
    var deletions: Set<Int> = []

    var added: Int { lines.values.filter { $0 == .added }.count }
    var modified: Int { lines.values.filter { $0 == .modified }.count }
    var isEmpty: Bool { lines.isEmpty && deletions.isEmpty }

    static func compute(base: String, current: String) -> ChangeMarkers {
        let old = base.components(separatedBy: "\n")
        let new = current.components(separatedBy: "\n")
        guard old != new else { return ChangeMarkers() }
        let diff = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var markers = ChangeMarkers()
        var i = 0, j = 0, pendingRemovals = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) {
                pendingRemovals += 1
                i += 1
            } else if j < new.count && inserted.contains(j) {
                if pendingRemovals > 0 {
                    markers.lines[j] = .modified
                    pendingRemovals -= 1
                } else {
                    markers.lines[j] = .added
                }
                j += 1
            } else {
                if pendingRemovals > 0 { markers.deletions.insert(j); pendingRemovals = 0 }
                i += 1
                j += 1
            }
        }
        if pendingRemovals > 0 { markers.deletions.insert(max(0, new.count - 1)) }
        return markers
    }
}

enum GitBase {
    /// 파일이 git 저장소에 있으면 마지막 커밋(HEAD)의 내용
    static func headContent(of file: URL) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let git = URL(fileURLWithPath: "/usr/bin/git")
            guard FileManager.default.isExecutableFile(atPath: git.path) else { return nil }
            let process = Process()
            process.executableURL = git
            // 남이 만든 저장소의 설정이 다른 명령을 실행하지 못하게:
            // cat-file(필터·textconv 없이 그대로 읽기) + 위험한 설정 끄기 + 묻기·잠금 끄기
            process.arguments = [
                "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "protocol.allow=never",
                "-c", "core.sshCommand=false", "-c", "credential.helper=",
                "-C", file.deletingLastPathComponent().path,
                "cat-file", "blob", "HEAD:./" + file.lastPathComponent,
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_OPTIONAL_LOCKS"] = "0"
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            environment["GIT_ASKPASS"] = "/usr/bin/false"
            environment["SSH_ASKPASS"] = "/usr/bin/false"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            do { try process.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return MarkdownDocument.decode(data)
        }.value
    }
}

/// 파일이 다른 앱에서 바뀌는지 지켜봅니다. 저장할 때 파일을 통째로 바꿔치기하는 앱도 따라갑니다.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                               eventMask: [.write, .extend, .delete, .rename, .attrib],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let src = self.source else { return }
            let flags = src.data
            self.onChange()
            if flags.contains(.delete) || flags.contains(.rename) {
                src.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.start() }
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }
}
