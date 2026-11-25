import Foundation
import JavaScriptCore
import Quartz
import UniformTypeIdentifiers

/// Finder 훑어보기(스페이스 바)용 미리보기.
/// 앱과 같은 마크다운 변환기(markdown.js)를 JavaScriptCore 로 실행해 HTML 을 만들어 돌려줍니다.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let text = Self.decode(data)
        let html = Self.page(body: try Self.render(text), title: request.fileURL.deletingPathExtension().lastPathComponent)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 860, height: 1000)) { _ in
            Data(html.utf8)
        }
    }

    private static func resource(_ name: String, _ ext: String) -> String {
        let bundle = Bundle(for: PreviewProvider.self)
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    private static func render(_ text: String) throws -> String {
        guard let context = JSContext() else { throw CocoaError(.featureUnsupported) }
        context.evaluateScript("var window = this;")
        context.evaluateScript(resource("highlight", "js"))
        context.evaluateScript(resource("markdown", "js"))
        guard let render = context.objectForKeyedSubscript("Markdown")?.objectForKeyedSubscript("render"),
              let html = render.call(withArguments: [text])?.toString() else {
            throw CocoaError(.featureUnsupported)
        }
        return sanitize(html)
    }

    /// 훑어보기에서는 스크립트가 필요 없으므로 실행될 만한 것은 모두 걷어냅니다.
    private static func sanitize(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<(script|iframe|object|embed|style|link|meta|base|form)\b[\s\S]*?(?:</\1\s*>|/?>)"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2"#,
                                   with: "$1=\"#\"", options: [.regularExpression, .caseInsensitive])
        return s
    }

    private static func page(body: String, title: String) -> String {
        let template = resource("preview", "html")
        var style = ""
        if let start = template.range(of: "<style>"), let end = template.range(of: "</style>") {
            style = String(template[start.lowerBound..<end.upperBound])
        }
        let safeTitle = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html lang="ko">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(safeTitle)</title>
        \(style)
        </head>
        <body>
        <article id="content">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) {
            return s
        }
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        if let s = String(data: data, encoding: cp949) { return s }
        return String(decoding: data, as: UTF8.self)
    }
}
