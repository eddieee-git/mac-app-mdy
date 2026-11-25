import AppKit

/// 표 편집: Tab 으로 칸 이동, Enter 로 행 추가, 세로줄 자동 정렬, 행·열 추가·삭제
extension EditorController {
    struct TableContext {
        var firstLine: Int
        var lastLine: Int
        var table: MarkdownTable
        /// 0 = 머리글, 1… = 본문 행
        var row: Int
        var column: Int
    }

    func tableContext() -> TableContext? {
        let caret = textView.selectedRange().location
        let current = line(at: caret)
        let count = lineCount
        func isRow(_ l: Int) -> Bool {
            let t = text(ofLine: l)
            return t.contains("|") && !t.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard isRow(current) else { return nil }
        var first = current, last = current
        while first > 0 && isRow(first - 1) { first -= 1 }
        while last + 1 < count && isRow(last + 1) { last += 1 }
        // 구분 줄(---) 바로 위 줄이 표의 시작
        guard let separator = (first...last).first(where: { MarkdownTable.isSeparator(text(ofLine: $0)) }),
              separator > first else { return nil }
        first = separator - 1
        guard current >= first,
              let table = MarkdownTable(lines: (first...last).map { text(ofLine: $0) }) else { return nil }

        let row = current <= separator ? 0 : current - separator
        // 커서 앞의 | 개수로 칸 번호를 셉니다.
        let lineText = text(ofLine: current)
        let offset = caret - lineStart(current)
        let before = String((lineText as NSString).substring(to: min(offset, (lineText as NSString).length)))
        var pipes = 0
        var inCode = false
        var previous: Character = " "
        for ch in before {
            if ch == "`" { inCode.toggle() }
            if ch == "|" && previous != "\\" && !inCode { pipes += 1 }
            previous = ch
        }
        if lineText.trimmingCharacters(in: .whitespaces).hasPrefix("|") { pipes -= 1 }
        let column = max(0, min(pipes, table.columnCount - 1))
        return TableContext(firstLine: first, lastLine: last, table: table, row: row, column: column)
    }

    /// 표를 칸 맞춰 다시 쓰고, 커서를 (row, column) 칸으로 옮깁니다.
    func writeTable(_ table: MarkdownTable, over context: TableContext, row: Int, column: Int,
                    selectCell: Bool = true, trailing: String = "") {
        let (lines, starts) = table.formatted()
        let start = lineStart(context.firstLine)
        let end = NSMaxRange(characterRange(lines: context.lastLine, context.lastLine))
        let text = lines.joined(separator: "\n") + trailing
        let r = max(0, min(row, table.rows.count - 1))
        let c = max(0, min(column, starts[r].count - 1))
        let lineIndex = r == 0 ? 0 : r + 1
        let offset = lines.prefix(lineIndex).reduce(0) { $0 + ($1 as NSString).length + 1 } + starts[r][c]
        let cell = r < table.rows.count && c < table.rows[r].count ? table.rows[r][c] : ""
        var selection = NSRange(location: start + offset, length: selectCell ? (cell as NSString).length : 0)
        if !trailing.isEmpty { selection = NSRange(location: start + (text as NSString).length, length: 0) }
        replace(NSRange(location: start, length: end - start), with: text, select: selection)
    }

    func tableTab(forward: Bool) -> Bool {
        guard autoList, let context = tableContext() else { return false }
        var table = context.table
        var r = context.row, c = context.column
        if forward {
            c += 1
            if c >= table.columnCount {
                c = 0
                r += 1
                if r >= table.rows.count { table.rows.append(Array(repeating: "", count: table.columnCount)) }
            }
        } else {
            c -= 1
            if c < 0 {
                r -= 1
                c = table.columnCount - 1
                if r < 0 { r = 0; c = 0 }
            }
        }
        writeTable(table, over: context, row: r, column: c)
        return true
    }

    func tableNewline() -> Bool {
        guard autoList, textView.selectedRange().length == 0, let context = tableContext() else { return false }
        var table = context.table
        let r = context.row
        // 마지막 빈 행에서 Enter → 그 행을 지우고 표에서 나가기
        if r > 0, r == table.rows.count - 1, table.rows[r].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            table.rows.removeLast()
            writeTable(table, over: context, row: 0, column: 0, selectCell: false, trailing: "\n")
            return true
        }
        table.rows.insert(Array(repeating: "", count: table.columnCount), at: r + 1)
        writeTable(table, over: context, row: r + 1, column: 0, selectCell: false)
        return true
    }

    // MARK: 메뉴 명령

    func insertTable() {
        let table = MarkdownTable.empty(columns: 3, rows: 2)
        let sel = textView.selectedRange()
        insertBlock(table.formatted().lines.joined(separator: "\n"), at: sel)
        // 첫 머리글 칸 선택
        let caretLine = line(at: textView.selectedRange().location) - 4
        if caretLine >= 0 {
            let start = lineStart(caretLine) + 2
            textView.setSelectedRange(NSRange(location: start, length: (table.rows[0][0] as NSString).length))
        }
    }

    func formatTable() {
        guard let context = tableContext() else { NSSound.beep(); return }
        writeTable(context.table, over: context, row: context.row, column: context.column, selectCell: false)
    }

    func addTableRow() {
        guard let context = tableContext() else { NSSound.beep(); return }
        var table = context.table
        table.rows.insert(Array(repeating: "", count: table.columnCount), at: context.row + 1)
        writeTable(table, over: context, row: context.row + 1, column: context.column, selectCell: false)
    }

    func addTableColumn() {
        guard let context = tableContext() else { NSSound.beep(); return }
        var table = context.table
        let columns = table.columnCount
        let at = min(context.column + 1, columns)
        for i in table.rows.indices {
            while table.rows[i].count < columns { table.rows[i].append("") }
            table.rows[i].insert(i == 0 ? tr("제목") : "", at: at)
        }
        while table.aligns.count < at { table.aligns.append(.none) }
        table.aligns.insert(.none, at: at)
        writeTable(table, over: context, row: context.row, column: at)
    }

    func deleteTableRow() {
        guard let context = tableContext(), context.row > 0 else { NSSound.beep(); return }
        var table = context.table
        table.rows.remove(at: context.row)
        writeTable(table, over: context, row: min(context.row, table.rows.count - 1), column: context.column, selectCell: false)
    }

    func deleteTableColumn() {
        guard let context = tableContext(), context.table.columnCount > 1 else { NSSound.beep(); return }
        var table = context.table
        for i in table.rows.indices where context.column < table.rows[i].count { table.rows[i].remove(at: context.column) }
        if context.column < table.aligns.count { table.aligns.remove(at: context.column) }
        writeTable(table, over: context, row: context.row, column: max(0, context.column - 1), selectCell: false)
    }
}
