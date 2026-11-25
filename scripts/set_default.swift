// 지정한 앱을 Markdown(.md) 파일의 기본 앱으로 설정합니다.
import AppKit
import UniformTypeIdentifiers

let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
let type = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md")!
let done = DispatchSemaphore(value: 0)
var failed = false

NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
    if let error {
        FileHandle.standardError.write("기본 앱 지정 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
        failed = true
    }
    done.signal()
}
done.wait()
exit(failed ? 1 : 0)
