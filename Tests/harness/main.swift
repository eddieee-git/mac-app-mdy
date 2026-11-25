// 편집기 동작 시험: 앱 소스(MdyApp.swift 제외)와 함께 컴파일해서 돌려요. scripts/test.sh 가 불러요.
import AppKit

@main
struct TestMain {
    @MainActor static func main() {
        _ = NSApplication.shared
        // 사용: <시험 프로그램> Resources/Help.md <작업 폴더>
        let work = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : NSTemporaryDirectory()
        var failures = 0
        func check(_ name: String, _ got: String, _ want: String) {
            if got == want { print("✓", name) } else { failures += 1; print("✗", name, "\n   got: ", got.debugDescription, "\n   want:", want.debugDescription) }
        }
        let e = EditorController()
        let tv = e.textView
        func run(_ text: String, caret: Int, sel: Int = 0, _ action: () -> Void) -> String {
            e.setText(text)
            tv.setSelectedRange(NSRange(location: caret, length: sel))
            action()
            return tv.string
        }
        let newline = { _ = e.textView(tv, doCommandBy: #selector(NSResponder.insertNewline(_:))) }
        check("bullet continue", run("- a", caret: 3, newline), "- a\n- ")
        check("ordered continue", run("9. a", caret: 4, newline), "9. a\n10. ")
        check("task continue", run("- [x] done", caret: 10, newline), "- [x] done\n- [ ] ")
        check("empty item ends list", run("- a\n- ", caret: 6, newline), "- a\n")
        check("quote continue", run("> hi", caret: 4, newline), "> hi\n> ")
        check("plain newline untouched", run("abc", caret: 3, newline), "abc")
        check("tab indents", run("- a", caret: 3, { _ = e.textView(tv, doCommandBy: #selector(NSResponder.insertTab(_:))) }), "  - a")
        check("backtab outdents", run("  - a", caret: 5, { _ = e.textView(tv, doCommandBy: #selector(NSResponder.insertBacktab(_:))) }), "- a")
        check("bold selection", run("hello world", caret: 0, sel: 5, { e.toggleWrap("**") }), "**hello** world")
        check("bold unwrap", run("**hello** world", caret: 2, sel: 5, { e.toggleWrap("**") }), "hello world")
        check("bold word at caret", run("say 안녕 now", caret: 5, { e.toggleWrap("**") }), "say **안녕** now")
        NSPasteboard.general.clearContents()
        check("link", run("site", caret: 0, sel: 4, { e.insertLink() }), "[site](주소)")
        check("heading", run("title\nbody", caret: 2, { e.setHeading(2) }), "## title\nbody")
        check("heading off", run("### t", caret: 2, { e.setHeading(0) }), "t")


        check("replace lines", run("a\nb\nc\nd", caret: 0, { e.replaceLines(1, 2, with: "X\nY\nZ") }), "a\nX\nY\nZ\nd")
        check("replace into empty doc", run("", caret: 0, { e.replaceLines(0, 0, with: "# 새 글") }), "# 새 글")
        check("toggle task on", run("- [ ] a\n- [x] b", caret: 0, { e.toggleTask(line: 0) }), "- [x] a\n- [x] b")
        check("toggle task off", run("1. [X] a", caret: 0, { e.toggleTask(line: 0) }), "1. [ ] a")
        do {
            let um = UndoManager()
            final class D: NSObject, NSTextViewDelegate { let um: UndoManager; init(_ u: UndoManager) { um = u }
                func undoManager(for view: NSTextView) -> UndoManager? { um } }
            _ = um
        }

        // ── 표
        let tbl = "| a | b |\n|---|---|\n| 1 | 2 |"
        check("table tab next cell", run(tbl, caret: 2, { _ = e.textView(tv, doCommandBy: #selector(NSResponder.insertTab(_:))) }),
              "| a   | b   |\n| --- | --- |\n| 1   | 2   |")
        print("   selection after tab:", (tv.string as NSString).substring(with: tv.selectedRange()).debugDescription)
        check("table tab adds row at end", run("| a | b |\n|---|---|\n| 1 | 2 |", caret: 30, { _ = e.textView(tv, doCommandBy: #selector(NSResponder.insertTab(_:))) }),
              "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n|     |     |")
        check("table enter new row", run(tbl, caret: 24, newline), "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n|     |     |")
        check("table enter on empty last row exits", run("| a | b |\n|---|---|\n|  |  |", caret: 23, newline), "| a   | b   |\n| --- | --- |\n")
        check("korean width align", run("| 이름 | x |\n|:-:|--:|\n| 가 | 12345 |", caret: 0, { e.formatTable() }),
              "| 이름  |     x |\n| :---: | ----: |\n|  가   | 12345 |")
        check("add column", run(tbl, caret: 2, { e.addTableColumn() }), "| a   | 제목 | b   |\n| --- | ---- | --- |\n| 1   |      | 2   |")
        check("delete row", run(tbl, caret: 24, { e.deleteTableRow() }), "| a   | b   |\n| --- | --- |")

        // ── 붙여넣기
        let pb = NSPasteboard(name: NSPasteboard.Name("mdy-test"))
        func paste(_ text: String, into: String, sel: NSRange) -> String {
            e.setText(into); tv.setSelectedRange(sel)
            pb.clearContents(); pb.setString(text, forType: .string)
            _ = e.handlePaste(pb, at: nil)
            return tv.string
        }
        check("url over selection → link", paste("https://apple.com", into: "see Apple now", sel: NSRange(location: 4, length: 5)), "see [Apple](https://apple.com) now")
        check("tsv → table", paste("이름\t나이\n철수\t20\n", into: "", sel: NSRange(location: 0, length: 0)),
              "| 이름 | 나이 |\n| ---- | ---- |\n| 철수 | 20   |\n")
        check("plain paste untouched", paste("hello", into: "", sel: NSRange(location: 0, length: 0)), "")
        print("   (plain text returns false → system pastes)")
        check("looks formatted: bold", EditorController.looksFormatted("<p>a <b>b</b></p>") ? "y" : "n", "y")
        check("looks formatted: vscode", EditorController.looksFormatted("<div style=\"white-space: pre;font-family: Menlo\"><span>x</span></div>") ? "y" : "n", "n")

        // ── 짝 맞추기
        let typing = NSRange(location: NSNotFound, length: 0)
        check("pair paren", run("", caret: 0, { tv.insertText("(", replacementRange: typing) }), "()")
        check("skip closer", run("", caret: 0, { tv.insertText("(", replacementRange: typing); tv.insertText("x", replacementRange: typing); tv.insertText(")", replacementRange: typing) }), "(x)")
        check("wrap selection *", run("word", caret: 0, sel: 4, { tv.insertText("*", replacementRange: typing) }), "*word*")
        check("no pair before word", run("abc", caret: 0, { tv.insertText("(", replacementRange: typing) }), "(abc")
        check("fence backticks", run("", caret: 0, { for _ in 0..<3 { tv.insertText("`", replacementRange: typing) } }), "```")
        check("delete empty pair", run("()", caret: 1, { tv.deleteBackward(nil) }), "")
        check("star alone no pair", run("", caret: 0, { tv.insertText("*", replacementRange: typing) }), "*")

        // ── 접기
        let doc = "# A\none\ntwo\n# B\nthree"
        e.setText(doc)
        let lm2 = tv.layoutManager!, tc2 = tv.textContainer!
        lm2.ensureLayout(for: tc2)
        let before = lm2.usedRect(for: tc2).height
        e.foldAll()
        lm2.ensureLayout(for: tc2)
        let after = lm2.usedRect(for: tc2).height
        print(after < before * 0.7 ? "✓" : "✗", "fold hides lines (height \(Int(before)) → \(Int(after)))")
        check("fold keeps text", tv.string, doc)
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        e.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        lm2.ensureLayout(for: tc2)
        print(e.isFolded(line: 0) ? "✗" : "✓", "caret into fold unfolds it")
        e.unfoldAll()

        // ── 바뀐 줄
        let m = ChangeMarkers.compute(base: "a\nb\nc\nd", current: "a\nB\nc\nnew\nd")
        check("change markers", "\(m.lines.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })", "[\"1:modified\", \"3:added\"]")
        let d = ChangeMarkers.compute(base: "a\nb\nc", current: "a\nc")
        check("deletion marker", "\(d.deletions.sorted())", "[1]")

        // ── 링크 안전
        let dir = URL(fileURLWithPath: work + "/links", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func touch(_ name: String, exec: Bool = false) -> URL {
            let u = dir.appendingPathComponent(name); FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
            if exec { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path) }
            return u
        }
        func kind(_ d: LinkSafety.Decision) -> String { switch d { case .open: "open"; case .ask: "ask"; case .block: "block" } }
        check("link https", kind(LinkSafety.decide(URL(string: "https://apple.com")!)), "open")
        check("link custom scheme asks", kind(LinkSafety.decide(URL(string: "zoommtg://join?x=1")!)), "ask")
        check("link .command blocked", kind(LinkSafety.decide(touch("run.command"))), "block")
        check("link .app-ish .sh blocked", kind(LinkSafety.decide(touch("x.sh"))), "block")
        check("link no-ext executable blocked", kind(LinkSafety.decide(touch("tool", exec: true))), "block")
        check("link pdf opens", kind(LinkSafety.decide(touch("doc.pdf"))), "open")
        check("link missing file blocked", kind(LinkSafety.decide(dir.appendingPathComponent("nope.txt"))), "block")
        check("link folder opens (in Finder)", kind(LinkSafety.decide(dir)), "open")

        // ── git 기준 (cat-file)
        let repo = URL(fileURLWithPath: work + "/repo", isDirectory: true)
        try? FileManager.default.removeItem(at: repo)
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let file = repo.appendingPathComponent("a.md")
        try? Data("커밋한 내용\n".utf8).write(to: file)
        for args in [["init", "-q"], ["-c", "user.email=t@t", "-c", "user.name=t", "add", "a.md"],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "x"]] {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", repo.path] + args
            try? p.run(); p.waitUntilExit()
        }
        try? Data("바뀐 내용\n".utf8).write(to: file)
        let sem = DispatchSemaphore(value: 0)
        var head: String?
        Task.detached { head = await GitBase.headContent(of: file); sem.signal() }
        while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        check("git HEAD content", head ?? "nil", "커밋한 내용\n")
        // 색칠: 도움말 전체에 적용해도 문제없고 실제로 색이 들어가는지
        let help = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)  // Resources/Help.md
        e.setText(help)
        var colored = 0
        let lm = tv.layoutManager!
        var i = 0
        while i < (help as NSString).length {
            var r = NSRange()
            if lm.temporaryAttribute(.foregroundColor, atCharacterIndex: i, effectiveRange: &r) != nil { colored += 1 }
            i = max(i + 1, NSMaxRange(r))
        }
        print(colored > 50 ? "✓" : "✗", "colorizer painted \(colored) ranges")

        let outline = DocumentSession.outline(of: help)
        print("✓ outline:", outline.map { "\($0.level):\($0.title)" }.joined(separator: " | "))
        let s = DocumentSession.stats(of: "안녕 하세요\nhello")
        check("stats", "\(s.words) \(s.characters) \(s.charactersNoSpaces) \(s.lines)", "3 12 10 2")
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
