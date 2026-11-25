import AppKit

/// 원본 편집기의 마크다운 문법 색칠.
/// 글자 자체의 속성이 아니라 레이아웃 매니저의 임시 속성(글자색)만 바꿔서,
/// 저장되는 내용·실행 취소 기록·줄 배치에 영향을 주지 않습니다.
@MainActor
enum MarkdownColorizer {
    private struct Rule {
        let regex: NSRegularExpression
        let paint: (NSTextCheckingResult, (NSRange, NSColor) -> Void) -> Void
    }

    private static let heading = NSColor.systemBlue
    private static let strong = NSColor.systemOrange
    private static let emphasis = NSColor.systemPurple
    private static let code = NSColor.systemPink
    private static let link = NSColor.systemTeal
    private static let marker = NSColor.tertiaryLabelColor
    private static let listMarker = NSColor.systemOrange
    private static let quote = NSColor.secondaryLabelColor
    private static let quoteMarker = NSColor.systemGreen
    private static let html = NSColor.systemGray
    private static let math = NSColor.systemGreen
    private static let codeBlock = NSColor.secondaryLabelColor

    private static func re(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func valid(_ r: NSRange) -> Bool { r.location != NSNotFound && r.length > 0 }

    private static let rules: [Rule] = [
        // 제목
        Rule(regex: re(#"^ {0,3}(#{1,6})(?:[ \t].*)?$"#)) { m, c in c(m.range, heading); c(m.range(at: 1), marker) },
        // Setext 밑줄·구분선
        Rule(regex: re(#"^ {0,3}(?:=+|-{2,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})[ \t]*$"#)) { m, c in c(m.range, marker) },
        // 인용
        Rule(regex: re(#"^ {0,3}((?:>[ \t]?)+)(.*)$"#)) { m, c in c(m.range(at: 2), quote); c(m.range(at: 1), quoteMarker) },
        // 목록 기호·체크박스
        Rule(regex: re(#"^[ \t]*([-*+]|\d{1,9}[.)])(?=[ \t])([ \t]+\[[ xX]\])?"#)) { m, c in c(m.range(at: 1), listMarker); c(m.range(at: 2), listMarker) },
        // 표의 | 와 구분 줄
        Rule(regex: re(#"^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$"#)) { m, c in c(m.range, marker) },
        Rule(regex: re(#"(?<=^|[^\\])\|"#)) { m, c in c(m.range, marker) },
        // 굵게 / 기울임 / 취소선 / 형광펜
        Rule(regex: re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)) { m, c in
            c(m.range, strong)
            c(NSRange(location: m.range.location, length: 2), marker)
            c(NSRange(location: NSMaxRange(m.range) - 2, length: 2), marker)
        },
        Rule(regex: re(#"(?<![*\w\\])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_\\])\1(?![*\w])"#)) { m, c in
            c(m.range, emphasis)
            c(NSRange(location: m.range.location, length: 1), marker)
            c(NSRange(location: NSMaxRange(m.range) - 1, length: 1), marker)
        },
        Rule(regex: re(#"~~(?=\S).+?(?<=\S)~~"#)) { m, c in c(m.range, marker) },
        Rule(regex: re(#"==(?=\S)[^=\n]+?(?<=\S)=="#)) { m, c in c(m.range, strong) },
        // 링크·이미지 [글자](주소)
        Rule(regex: re(#"(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))"#)) { m, c in
            c(m.range, marker)
            c(m.range(at: 2), link)
        },
        Rule(regex: re(#"(!?\[)([^\]\n]+)(\]\[[^\]\n]*\])"#)) { m, c in c(m.range, marker); c(m.range(at: 2), link) },
        Rule(regex: re(#"\[\^[^\]\s]+\]"#)) { m, c in c(m.range, link) },
        Rule(regex: re(#"^ {0,3}\[[^\]]+\]:.*$"#)) { m, c in c(m.range, marker) },
        Rule(regex: re(#"<(?:https?|mailto|ftp):[^>\s]+>|(?<![(<\w])https?://[^\s<>)\]]+"#)) { m, c in c(m.range, link) },
        // HTML 태그·주석
        Rule(regex: re(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>\n]*)?/?>"#)) { m, c in c(m.range, html) },
        Rule(regex: re(#"<!--[\s\S]*?-->"#, [])) { m, c in c(m.range, marker) },
        // 수식 $...$
        Rule(regex: re(#"(?<![\\$])\$(?=[^\s$])[^$\n]+?(?<=\S)\$(?!\d)"#)) { m, c in c(m.range, math) },
        // 이스케이프
        Rule(regex: re(#"\\[^\w\s]"#)) { m, c in c(m.range, marker) },
        // 인라인 코드는 마지막에 칠해서 안쪽의 다른 색을 덮습니다.
        Rule(regex: re(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)) { m, c in c(m.range, code) },
    ]

    static func clear(_ layoutManager: NSLayoutManager, length: Int) {
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
    }

    static func apply(to layoutManager: NSLayoutManager, string: String) {
        let ns = string as NSString
        let full = NSRange(location: 0, length: ns.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        guard ns.length > 0 else { return }

        let paint: (NSRange, NSColor) -> Void = { range, color in
            guard valid(range) else { return }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
        }

        for rule in rules {
            rule.regex.enumerateMatches(in: string, options: [], range: full) { match, _, _ in
                if let match { rule.paint(match, paint) }
            }
        }

        // 코드 블록·수식 블록·머리말은 줄 단위로 찾아 통째로 덮어 칠합니다.
        var fence: (char: unichar, length: Int)?
        var mathBlock = false
        var frontMatter = false
        var lineIndex = 0
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            defer { lineIndex += 1 }
            let line = ns.substring(with: range)
            let trimmed = line.drop(while: { $0 == " " })
            let indent = line.count - trimmed.count

            if lineIndex == 0 && line == "---" { frontMatter = true; paint(range, marker); return }
            if frontMatter {
                if line == "---" || line == "..." { frontMatter = false; paint(range, marker) } else { paint(range, quote) }
                return
            }

            if let f = fence {
                let run = trimmed.prefix(while: { $0.utf16.first == f.char }).count
                if indent <= 3, run >= f.length, trimmed.dropFirst(run).allSatisfy(\.isWhitespace) {
                    fence = nil
                    paint(range, marker)
                } else {
                    paint(range, codeBlock)
                }
                return
            }
            if mathBlock {
                paint(range, math)
                if line.trimmingCharacters(in: .whitespaces).hasSuffix("$$") { mathBlock = false }
                return
            }
            if indent <= 3, let first = trimmed.first, first == "`" || first == "~" {
                let run = trimmed.prefix(while: { $0 == first }).count
                if run >= 3 {
                    fence = (first.utf16.first!, run)
                    paint(range, marker)
                    let info = (line as NSString).range(of: String(trimmed.dropFirst(run)).trimmingCharacters(in: .whitespaces))
                    if info.length > 0 { paint(NSRange(location: range.location + info.location, length: info.length), code) }
                    return
                }
            }
            if indent <= 3, trimmed.hasPrefix("$$") {
                paint(range, math)
                let rest = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !(rest.hasSuffix("$$") && !rest.isEmpty) { mathBlock = true }
                return
            }
        }
    }
}
