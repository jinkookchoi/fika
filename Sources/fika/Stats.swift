import Foundation

/// 완료한 작업 세션 한 건. (작업 → 휴식으로 정상 전환될 때 기록)
struct SessionRecord: Codable {
    let date: Date       // 세션 완료 시각
    let minutes: Double  // 그 세션 집중 시간(분)
}

/// 집중 세션 기록을 영구 저장하고 일/주/월 집계를 제공한다.
/// `~/Library/Application Support/Fika/sessions.json`
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var records: [SessionRecord] = []

    private let fileURL: URL
    private let cal = Calendar.current

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fika", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sessions.json")
        load()
    }

    /// 완료 세션 기록.
    func record(minutes: Double, at date: Date) {
        guard minutes > 0 else { return }
        records.append(SessionRecord(date: date, minutes: minutes))
        save()
    }

    // MARK: - 집계

    private func sum(since start: Date) -> (sessions: Int, minutes: Double) {
        let recent = records.filter { $0.date >= start }
        return (recent.count, recent.reduce(0) { $0 + $1.minutes })
    }

    var today: (sessions: Int, minutes: Double) { sum(since: cal.startOfDay(for: Date())) }

    var thisWeek: (sessions: Int, minutes: Double) {
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return sum(since: start)
    }

    var thisMonth: (sessions: Int, minutes: Double) {
        let start = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        return sum(since: start)
    }

    /// 최근 `days`일의 일별 집중 시간. (기록 없는 날도 0으로 포함, 과거→오늘 순)
    func dailySeries(days: Int) -> [(date: Date, minutes: Double)] {
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let mins = records.filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.minutes }
            return (day, mins)
        }
    }

    /// 최근 `weeks`주의 주별 집중 시간. (과거→이번 주 순)
    func weeklySeries(weeks: Int) -> [(date: Date, minutes: Double)] {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<weeks).reversed().map { offset in
            let start = cal.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) ?? thisWeek
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let mins = records.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.minutes }
            return (start, mins)
        }
    }

    /// 최근 `months`개월의 월별 집중 시간. (과거→이번 달 순)
    func monthlySeries(months: Int) -> [(date: Date, minutes: Double)] {
        let thisMonth = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        return (0..<months).reversed().map { offset in
            let start = cal.date(byAdding: .month, value: -offset, to: thisMonth) ?? thisMonth
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            let mins = records.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.minutes }
            return (start, mins)
        }
    }

    /// "N시간 NN분" / "NN분" 형식.
    static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }

    // MARK: - 저장/로드

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) else { return }
        records = decoded
    }
}
