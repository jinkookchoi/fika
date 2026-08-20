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
        invalidate()
        save()
    }

    // MARK: - 집계
    //
    // today/thisWeek/thisMonth 는 패널 홈 탭 body 에서 매번 읽힌다(진행 링 때문에 초당 수십 번).
    // 매번 계산하면 기록 수 × 호출 수만큼 스캔이 늘어 **앱을 오래 쓸수록 무거워진다.**
    // 그래서 세 값을 한 번에 계산해 캐시하고, 기록이 바뀌거나 날이 바뀔 때만 다시 센다.
    // `Calendar.startOfDay`/`dateInterval(of:for:)` 도 비싸서 재계산할 때만 부른다
    // (평소엔 만료 시각과 Date 비교 한 번으로 끝난다).

    typealias Tally = (sessions: Int, minutes: Double)

    private var cached: (today: Tally, week: Tally, month: Tally)?
    /// 캐시가 유효한 시각의 끝 = 다음 자정. 주/월 경계는 항상 날 경계와 함께 넘어가므로 이것만 보면 된다.
    private var cacheExpiry = Date.distantPast

    /// 기록이 바뀌면 캐시를 버린다.
    private func invalidate() {
        cached = nil
        cacheExpiry = .distantPast
    }

    private func tallies() -> (today: Tally, week: Tally, month: Tally) {
        let now = Date()
        if let c = cached, now < cacheExpiry { return c }

        let dayStart = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? dayStart

        // 한 번만 순회하면서 세 구간을 동시에 센다. (주 시작이 달 시작보다 이를 수 있어 조건은 각각 독립)
        var d: Tally = (0, 0), w: Tally = (0, 0), m: Tally = (0, 0)
        for r in records {
            if r.date >= monthStart { m.sessions += 1; m.minutes += r.minutes }
            if r.date >= weekStart  { w.sessions += 1; w.minutes += r.minutes }
            if r.date >= dayStart   { d.sessions += 1; d.minutes += r.minutes }
        }

        let result = (today: d, week: w, month: m)
        cached = result
        cacheExpiry = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now.addingTimeInterval(60)
        return result
    }

    var today: Tally { tallies().today }
    var thisWeek: Tally { tallies().week }
    var thisMonth: Tally { tallies().month }

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
        invalidate()
    }
}
