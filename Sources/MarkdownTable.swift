import Foundation

/// 마크다운 표: 읽기, 칸 맞춤 정렬, 행·열 편집
struct MarkdownTable {
    enum Align { case none, left, center, right }

    /// rows[0] 은 머리글. 구분 줄(---)은 aligns 로 따로 보관합니다.
    var rows: [[String]]
    var aligns: [Align]

    var columnCount: Int { max(aligns.count, rows.map(\.count).max() ?? 0) }

    static let separatorPattern = try! NSRegularExpression(
        pattern: #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#)

    static func isSeparator(_ line: String) -> Bool {
        line.contains("-") && separatorPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// | 로 칸을 나눕니다. \| 와 `코드` 안의 | 는 나누지 않습니다.
    static func split(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") { s.removeLast() }
        var cells: [String] = []
        var current = ""
        var inCode = false
        var previous: Character = " "
        for ch in s {
            if ch == "`" { inCode.toggle() }
            if ch == "|" && previous != "\\" && !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            previous = ch
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    init(rows: [[String]], aligns: [Align]) {
        self.rows = rows
        self.aligns = aligns
    }

    /// 첫 줄이 머리글, 둘째 줄이 구분 줄인 표 줄들을 읽습니다.
    init?(lines: [String]) {
        guard lines.count >= 2, Self.isSeparator(lines[1]) else { return nil }
        aligns = Self.split(lines[1]).map { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            switch (c.hasPrefix(":"), c.hasSuffix(":")) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            default: return .none
            }
        }
        rows = [Self.split(lines[0])] + lines.dropFirst(2).map(Self.split)
    }

    /// 탭으로 나뉜 표(엑셀·넘버스에서 복사한 내용)를 읽습니다.
    init?(tsv: String) {
        let lines = tsv.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return nil }
        let parsed = lines.map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: "\\|") } }
        let cols = parsed.map(\.count)
        guard let first = cols.first, first >= 2, cols.allSatisfy({ abs($0 - first) <= 1 }) else { return nil }
        rows = parsed
        aligns = Array(repeating: .none, count: parsed.map(\.count).max() ?? first)
    }

    /// 칸 폭을 맞춘 줄들과, 각 칸 내용이 시작하는 글자 위치(UTF-16)를 돌려줍니다.
    /// cellStarts[행][열] — 행 0 은 머리글, 구분 줄은 제외.
    func formatted() -> (lines: [String], cellStarts: [[Int]]) {
        let cols = max(1, columnCount)
        let grid = rows.map { $0 + Array(repeating: "", count: max(0, cols - $0.count)) }
        let aligns = self.aligns + Array(repeating: Align.none, count: max(0, cols - self.aligns.count))
        var widths = (0..<cols).map { c in max(3, grid.map { Self.displayWidth($0[c]) }.max() ?? 3) }
        for c in 0..<cols where aligns[c] == .center { widths[c] = max(widths[c], 5) }

        func pad(_ text: String, _ width: Int, _ align: Align) -> String {
            let space = max(0, width - Self.displayWidth(text))
            switch align {
            case .right: return String(repeating: " ", count: space) + text
            case .center:
                let left = space / 2
                return String(repeating: " ", count: left) + text + String(repeating: " ", count: space - left)
            default: return text + String(repeating: " ", count: space)
            }
        }

        var lines: [String] = []
        var starts: [[Int]] = []
        for (r, row) in grid.enumerated() {
            var line = "|"
            var rowStarts: [Int] = []
            for c in 0..<cols {
                line += " "
                let padded = pad(row[c], widths[c], aligns[c])
                let leading = padded.prefix(while: { $0 == " " }).utf16.count
                rowStarts.append(line.utf16.count + (row[c].isEmpty ? 0 : leading))
                line += padded + " |"
            }
            lines.append(line)
            starts.append(rowStarts)
            if r == 0 {
                let separator = (0..<cols).map { c -> String in
                    let dashes = String(repeating: "-", count: widths[c])
                    switch aligns[c] {
                    case .left: return ":" + dashes.dropFirst()
                    case .right: return dashes.dropFirst() + ":"
                    case .center: return ":" + dashes.dropFirst().dropLast() + ":"
                    case .none: return dashes
                    }
                }
                lines.append("| " + separator.joined(separator: " | ") + " |")
            }
        }
        return (lines, starts)
    }

    /// 화면 폭: 한글·한자·전각 문자와 이모지는 2칸
    static func displayWidth(_ text: String) -> Int {
        var width = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            switch v {
            case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
                 0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
                width += 2
            case 0x0300...0x036F, 0x200B...0x200F, 0xFE00...0xFE0F:
                break
            default:
                width += 1
            }
        }
        return width
    }

    static func empty(columns: Int, rows: Int) -> MarkdownTable {
        let header = (1...columns).map { tr("제목\($0)") }
        let body = Array(repeating: Array(repeating: "", count: columns), count: rows)
        return MarkdownTable(rows: [header] + body, aligns: Array(repeating: .none, count: columns))
    }
}
