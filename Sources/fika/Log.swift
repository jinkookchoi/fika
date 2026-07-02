import Foundation
import AppKit

/// 파일 기반 로거. `~/Library/Logs/Fika/Fika.log` 에 기록한다.
/// - `event`: 항상 남기는 중요한 이벤트(시작/종료/sleep·wake/예외)
/// - `debug`: 디버그 모드일 때만 남기는 상세 로그(상태 전환·오버레이 등)
enum Log {
    /// 디버그 모드 여부. AppSettings.debugMode 와 동기화된다.
    static var debugEnabled = false

    static let directory: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Fika", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let fileURL = directory.appendingPathComponent("Fika.log")

    private static let queue = DispatchQueue(label: "com.jinkookchoi.fika.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func event(_ msg: String) { queue.async { write("•", msg) } }
    static func debug(_ msg: String) {
        guard debugEnabled else { return }
        queue.async { write("·", msg) }
    }

    private static var writeCount = 0

    /// 실제 파일 기록. (queue 안에서, 또는 크래시 핸들러에서 동기로 호출)
    private static func write(_ tag: String, _ msg: String) {
        // 메뉴바 앱은 몇 주씩 안 꺼진다 → 시작 시 1회 회전만으론 부족. 주기적으로 크기를 확인한다(C-2).
        // rotateIfNeeded는 상한 초과 시에만 실제로 회전하므로 비용은 stat 한 번 수준.
        writeCount += 1
        if writeCount % 200 == 0 { rotateIfNeeded() }
        let line = "\(fmt.string(from: Date())) \(tag) \(msg)\n"
        NSLog("[Fika] %@", msg)
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: fileURL) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// 로그가 너무 커지면 한 세대만 보관하고 새로 시작한다.
    static func rotateIfNeeded(maxBytes: Int = 512_000) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attrs?[.size] as? Int, size > maxBytes else { return }
        let old = directory.appendingPathComponent("Fika.old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }

    /// 미처리 ObjC 예외(NSException)를 로그에 남긴다.
    /// 크래시 리포트에 reason 이 비는 경우가 있어, 이유와 스택을 직접 기록해 둔다.
    /// (단, 신형 macOS 는 메인 스레드 예외를 이 핸들러 전에 트랩할 수 있어 항상 잡히진 않는다.)
    static func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exc in
            let stack = exc.callStackSymbols.joined(separator: "\n")
            Log.write("✖︎", "UNCAUGHT \(exc.name.rawValue): \(exc.reason ?? "(no reason)")\n\(stack)")
        }
    }
}
