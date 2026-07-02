import Foundation

/// 최근 발화한 토스트 알림의 이력(자가진단용). 메모리 링버퍼 — 최근 N건만 유지한다.
/// "알림이 안 온 건지, 놓친 건지"를 사용자가 패널(알림 탭)에서 바로 판별하도록.
@MainActor
final class NotificationLog: ObservableObject {
    static let shared = NotificationLog()
    private init() {}

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let kind: String   // 동작 / 남은시간 / 마무리 / 고정휴식 / 시작
        let text: String
    }

    private let limit = 20
    /// 최신이 앞(index 0).
    @Published private(set) var entries: [Entry] = []

    func record(_ kind: String, _ text: String) {
        entries.insert(Entry(date: Date(), kind: kind, text: text), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }
}
