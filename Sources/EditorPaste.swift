import AppKit

/// 똑똑한 붙여넣기: 이미지 → 파일로 저장, 선택한 글자 위에 주소 → 링크,
/// 엑셀·넘버스 칸 → 마크다운 표, 웹·문서 앱의 서식 → 마크다운
extension EditorController {
    func handlePaste(_ pasteboard: NSPasteboard, at index: Int?) -> Bool {
        if insertImages(from: pasteboard, at: index) { return true }

        let plain = pasteboard.string(forType: .string)
        let target = index.map { NSRange(location: $0, length: 0) } ?? textView.selectedRange()
        let ns = textView.string as NSString

        // 선택한 글자 위에 주소를 붙여넣으면 링크로
        if index == nil, target.length > 0, let url = plain?.trimmingCharacters(in: .whitespacesAndNewlines), Self.isURL(url) {
            let selected = ns.substring(with: target)
            if !selected.contains("\n") {
                let link = "[\(selected)](\(url))"
                replace(target, with: link, select: NSRange(location: target.location + (link as NSString).length, length: 0))
                return true
            }
        }

        // 엑셀·넘버스에서 복사한 칸 → 표
        if let plain, plain.contains("\t"), let table = MarkdownTable(tsv: plain) {
            insertBlock(table.formatted().lines.joined(separator: "\n"), at: target)
            return true
        }

        // 서식 있는 글 → 마크다운
        guard convertRichPaste, let converter = richPasteConverter, let html = Self.html(from: pasteboard),
              Self.looksFormatted(html) else { return false }
        converter(html) { [weak self] markdown in
            guard let self else { return }
            let text = (markdown?.isEmpty == false ? markdown : plain) ?? ""
            guard !text.isEmpty else { return }
            let range = NSRange(location: min(target.location, self.length),
                                length: min(target.length, self.length - min(target.location, self.length)))
            self.replace(range, with: text, select: NSRange(location: range.location + (text as NSString).length, length: 0))
        }
        return true
    }

    /// 표처럼 여러 줄짜리 덩어리는 앞뒤를 줄바꿈으로 떼어 넣습니다.
    func insertBlock(_ block: String, at range: NSRange) {
        let ns = textView.string as NSString
        var prefix = ""
        if range.location > 0 {
            let before = ns.substring(with: NSRange(location: range.location - 1, length: 1))
            prefix = before == "\n" ? "" : "\n\n"
            if before == "\n", range.location > 1, ns.substring(with: NSRange(location: range.location - 2, length: 1)) != "\n" {
                prefix = "\n"
            }
        }
        let text = prefix + block + "\n"
        replace(range, with: text, select: NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    private static func html(from pasteboard: NSPasteboard) -> String? {
        if let html = pasteboard.string(forType: .html) { return html }
        for type in [NSPasteboard.PasteboardType.rtfd, .rtf] {
            guard let data = pasteboard.data(forType: type) else { continue }
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] =
                [.documentType: type == .rtf ? NSAttributedString.DocumentType.rtf : .rtfd]
            guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
                  let htmlData = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
            else { continue }
            return String(data: htmlData, encoding: .utf8)
        }
        return nil
    }

    /// 굵게·목록·표·링크 같은 서식이 실제로 있는 HTML 인지.
    /// 코드 편집기(VS Code 등)에서 복사한 색칠된 코드는 서식으로 보지 않습니다.
    static func looksFormatted(_ html: String) -> Bool {
        let lower = html.lowercased()
        let codeEditor = lower.contains("white-space: pre") &&
            (lower.contains("monospace") || lower.contains("menlo") || lower.contains("consolas") || lower.contains("courier"))
        if codeEditor && !lower.contains("<table") { return false }
        if lower.range(of: #"<(b|strong|i|em|a\s|h[1-6]|ul|ol|table|blockquote|pre|img|del|s|mark)[\s>]"#, options: .regularExpression) != nil {
            return true
        }
        return lower.range(of: #"font-weight:\s*(bold|[6-9]00)|font-style:\s*italic"#, options: .regularExpression) != nil
    }

    // MARK: 이미지

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tif", "tiff", "bmp", "avif"]

    func insertImages(from pasteboard: NSPasteboard, at index: Int?) -> Bool {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let imageFiles = files.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
        let hasText = pasteboard.availableType(from: [.string, .html]) != nil
        let imageData: Data? = files.isEmpty && !hasText ? pngData(from: pasteboard) : nil

        guard !imageFiles.isEmpty || imageData != nil else { return false }
        guard let documentURL else {
            let alert = NSAlert()
            alert.messageText = tr("이미지를 넣으려면 먼저 문서를 저장해 주세요")
            alert.informativeText = tr("이미지는 문서 옆의 \"\(imageFolder)\" 폴더에 저장되고, 문서에는 상대 경로로 들어가요.")
            if let window = textView.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return true
        }

        let directory = documentURL.deletingLastPathComponent()
        var snippets: [String] = []
        do {
            for file in imageFiles {
                let path: String
                let base = directory.standardizedFileURL.path
                if file.standardizedFileURL.path.hasPrefix(base + "/") {
                    path = String(file.standardizedFileURL.path.dropFirst(base.count + 1))
                } else {
                    let target = try uniqueImageURL(in: directory, name: file.deletingPathExtension().lastPathComponent,
                                                    ext: file.pathExtension.lowercased())
                    try FileManager.default.copyItem(at: file, to: target)
                    path = imageFolder + "/" + target.lastPathComponent
                }
                snippets.append(imageMarkdown(alt: file.deletingPathExtension().lastPathComponent, path: path))
            }
            if let imageData {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let target = try uniqueImageURL(in: directory, name: "image-" + formatter.string(from: Date()), ext: "png")
                try imageData.write(to: target, options: .atomic)
                snippets.append(imageMarkdown(alt: "", path: imageFolder + "/" + target.lastPathComponent))
            }
        } catch {
            if let window = textView.window { NSAlert(error: error).beginSheetModal(for: window) }
            return true
        }

        if let index { textView.setSelectedRange(NSRange(location: index, length: 0)) }
        let text = snippets.joined(separator: "\n")
        let sel = textView.selectedRange()
        replace(sel, with: text, select: NSRange(location: sel.location + (text as NSString).length, length: 0))
        textView.window?.makeFirstResponder(textView)
        return true
    }

    private func imageMarkdown(alt: String, path: String) -> String {
        path.contains(" ") ? "![\(alt)](<\(path)>)" : "![\(alt)](\(path))"
    }

    private func uniqueImageURL(in directory: URL, name: String, ext: String) throws -> URL {
        let folder = directory.appendingPathComponent(imageFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
