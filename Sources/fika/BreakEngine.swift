import SwiftUI
import AppKit
import FikaCore

enum Phase: CustomStringConvertible {
    case working       // 작업 중
    case breaking      // 휴식 중
    case breakHold     // 휴식 시간은 끝났고, 사용자가 돌아오길 기다리는 중
    case paused        // 일시정지
    case scheduledRest // 고정 휴식 시간대(예: 점심) — 작업 사이클을 멈추고 쉼

    var description: String {
        switch self {
        case .working:       return "working"
        case .breaking:      return "breaking"
        case .breakHold:     return "breakHold"
        case .paused:        return "paused"
        case .scheduledRest: return "scheduledRest"
        }
    }
}

/// 작업/휴식 사이클을 관리하는 두뇌.
@MainActor
final class BreakEngine: ObservableObject {
    static let shared = BreakEngine()

    let settings = AppSettings()

    @Published private(set) var phase: Phase = .working
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isLongBreak = false
    /// 완료한 작업 세션 수 (긴 휴식 판정용)
    @Published private(set) var completedWork = 0
    /// 유휴 감지로 자리를 비웠다고 판단한 상태
    @Published private(set) var isAway = false

    /// 현재 단계의 전체 길이 (진행 링 계산용)
    @Published private(set) var phaseDuration: TimeInterval = 1
    private var phaseEnd: Date = .distantFuture
    private var pausedRemaining: TimeInterval = 0
    private var phaseBeforePause: Phase = .working
    /// "오늘은 그만"으로 조용해진 날짜키. 일반(수동) 일시정지와 구분하며, 날이 바뀐 뒤 복귀하면 자동 재개한다(A-4).
    private var quietDay: Int?
    private var timer: Timer?
    /// 직전 tick 시각. 이번 tick과의 간격이 크면(주로 시스템 sleep) 시간 보정을 한다(handleLongGap).
    /// 타이머를 죽이지 않고 이 gap만으로 sleep을 감지하므로 wake 알림 유실에 강하다.
    private var lastTick = Date()
    /// 다음 마이크로 브레이크(작업 중 동작 알림) 예정 시각
    private var nextMicroBreak: Date = .distantFuture
    /// 자리 비움이 시작된(입력이 끊긴) 시각. 복귀 시 비운 시간을 재서 휴식 인정 여부를 정한다(B-4).
    private var awayStart = Date()
    /// 다음에 띄울 "남은 시간 알림"의 목표 단계.
    /// 휴식까지 남은 시간이 `timeNoticeBucket × 주기(분)`에 도달하면 발화하고 한 단계 내린다(0이면 끝).
    /// 작업 시작이 아니라 "휴식까지 남은 시간" 기준이라, idle/sleep로 phaseEnd가 밀려도 정렬이 유지된다.
    private var timeNoticeBucket: Int = 0
    /// 카운트다운을 닫는 마지막 "곧 휴식" 알림을 이번 작업 세션에 이미 띄웠는지.
    private var timeNoticeFinalFired = false
    /// 이번 작업 세션에서 실제로 집중한 시간(초). 자리비움·일시정지·sleep 제외.
    /// enterBreak에서 이 값(계획 길이가 아니라 실제 집중분)을 기록하고 리셋한다(B-1·B-2).
    private var workedSeconds: TimeInterval = 0
    /// 하루 마무리 알림: 오늘 이미 쏜 단계(30/15/0)와 그 날짜키 (자정에 리셋)
    private var shutdownFiredStages: Set<Int> = []
    private var shutdownFiredDay = -1
    /// 고정 휴식 사전 예고: 오늘 이미 쐈는지 + 날짜키 (자정에 리셋)
    private var restPrealertFired = false
    private var restPrealertDay = -1
    private lazy var overlay = OverlayController(engine: self)

    /// 메뉴바 호버 팁 표시/숨김 (AppDelegate 의 트래킹에서 호출).
    func showMenuHoverTip(near anchor: NSRect) { overlay.showHoverTip(near: anchor) }
    func hideMenuHoverTip() { overlay.hideHoverTip() }

    private init() {
        settings.onScheduleChange = { [weak self] in self?.rescheduleAlerts() }   // A-7: 주기 설정 변경 → 재정렬
        startWork()
        startTimer()
        observeSleepWake()
    }

    /// 알림 주기 설정(남은시간/동작)이 세션 도중 바뀌면 현재 작업 세션의 스케줄을 새 값에 맞춰 재정렬한다(A-7).
    /// (안 하면: 주기를 줄이면 남은 세션 동안 알림이 거의 안 오고, 늘리면 다음 틱에 즉시 1발.)
    private func rescheduleAlerts() {
        guard phase == .working else { return }
        resetTimeNoticeBucket(forRemaining: remaining)
        nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.2   // A-8: 에너지 절약(정확도는 wall-clock으로 보정하므로 무해)
    }

    // MARK: - 파생 상태

    /// 작업이 곧 끝나 예고 배너를 보여줄 구간인지.
    var isWarning: Bool {
        phase == .working && remaining <= settings.warningSeconds && remaining > 0
    }

    /// 예고 강조 정도 0.0(여유) → 1.0(임박)
    var warningIntensity: Double {
        guard settings.warningSeconds > 0 else { return 1 }
        let p = 1 - (remaining / settings.warningSeconds)
        return min(max(p, 0), 1)
    }

    var phaseLabel: String {
        if isAway { return "자리 비움" }
        switch phase {
        case .working:       return isWarning ? "곧 휴식" : "작업 중"
        case .breaking:      return isLongBreak ? "긴 휴식" : "휴식 중"
        case .breakHold:     return "휴식 완료"
        case .paused:        return "일시정지"
        case .scheduledRest: return settings.scheduledRestLabel.isEmpty ? "예약 휴식" : settings.scheduledRestLabel
        }
    }

    var timeString: String { Self.mmss(remaining) }

    /// 토스트 표시용: 남은 시간을 분으로 반올림(최소 1분). (올림이면 9:29에도 "10분"으로 부풀어 시계와 어긋남)
    var remainingMinutesRounded: Int { max(1, Int((remaining / 60).rounded())) }

    /// 현재 상태에 맞는 마스코트 컷 이름 (cuts/<name>.png).
    var mascotCut: String {
        if phase == .breakHold { return "done" }
        if phase == .breaking || phase == .scheduledRest { return "resting" }
        if phase == .working && isWarning { return "warning" }
        return "work"
    }

    /// 메뉴바용 고정폭 시간 문자열 (분을 2자리로 패딩해 글자 수를 일정하게 유지).
    var menuTimeString: String { Self.mmss(remaining, padMinutes: true) }

    /// 남은 시간 비율 0~1 (진행 링용)
    var progress: Double {
        phaseDuration <= 0 ? 0 : min(1, max(0, remaining / phaseDuration))
    }

    /// 커피 잔 채움 정도 0(빔)~1(가득).
    /// 작업 중엔 남은 비율만큼 차 있다 점점 줄고(마심), 휴식 중엔 거꾸로 차오른다(리필).
    var coffeeLevel: Double {
        let activePhase = (phase == .paused) ? phaseBeforePause : phase
        switch activePhase {
        case .breaking, .scheduledRest: return 1 - progress   // 휴식하며 다시 채움
        case .breakHold: return 1              // 가득 채운 채 복귀 대기
        default:         return progress        // 작업하며 줄어듦 (자리비움 시 동결)
        }
    }

    /// 단계별 색 (진행 링·강조용)
    var phaseColor: Color {
        if isAway { return .gray }
        switch phase {
        case .working:   return isWarning ? .orange : Color(red: 0.83, green: 0.59, blue: 0.22)  // 앰버/카라멜
        case .breaking:  return isLongBreak ? .indigo : .teal
        case .breakHold: return .mint
        case .paused:    return .gray
        case .scheduledRest: return .teal
        }
    }

    /// 컬러 이모지 테마 글리프.
    var iconEmoji: String {
        if isAway { return "💤" }
        switch phase {
        case .working:   return isWarning ? "⏳" : "🌱"
        case .breaking:  return isLongBreak ? "🌙" : "☕️"
        case .breakHold: return "✅"
        case .paused:    return "⏸️"
        case .scheduledRest: return "☕️"
        }
    }

    /// SF 심볼 테마 이름.
    var iconSymbol: String {
        if isAway { return "moon.zzz.fill" }
        switch phase {
        case .working:   return isWarning ? "hourglass" : "leaf.fill"
        case .breaking:  return isLongBreak ? "moon.stars.fill" : "cup.and.saucer.fill"
        case .breakHold: return "checkmark.circle.fill"
        case .paused:    return "pause.fill"
        case .scheduledRest: return "cup.and.saucer.fill"
        }
    }

    static func mmss(_ t: TimeInterval, padMinutes: Bool = false) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: padMinutes ? "%02d:%02d" : "%d:%02d", s / 60, s % 60)
    }

    // MARK: - 틱

    private func tick() {
        let now = Date()
        let gap = now.timeIntervalSince(lastTick)
        lastTick = now
        if gap > 10, phase != .paused { handleLongGap(gap) }   // sleep 등 긴 공백을 tick 간격으로 감지·보정
        // 하루 마무리 알림은 시각 기반이라 상태머신과 독립 — 일시정지·고정 휴식 중에도 판정한다(A-5).
        // (아래 paused 가드나 handleScheduledRest return에 걸리면 그날 마무리 알림을 통째로 놓쳤음)
        handleShutdown()
        handleQuietForTodayResume()   // "오늘은 그만" 후 다음날 복귀 시 자동 재개(A-4)
        guard phase != .paused else { return }
        if handleScheduledRest() { return }   // 고정 휴식 시간대면 평소 로직을 건너뛴다
        if settings.idleResetEnabled {
            handleIdle()
        } else if isAway {
            isAway = false
        }
        if phase == .breakHold {
            handleBreakHold()
            refreshPresentation()
            return
        }
        remaining = max(0, phaseEnd.timeIntervalSinceNow)
        if phase == .working && !isAway { workedSeconds += 1 }   // 실제 집중 시간 누적(자리비움 제외)
        if remaining <= 0 {
            switch phase {
            case .working:  enterBreak()
            case .breaking: endBreak()
            case .breakHold, .paused, .scheduledRest: break
            }
        }
        handleMicroBreak()
        handleTimeNotice()
        handleFinalTimeNotice()
        handleScheduledRestPrealert()
        refreshPresentation()
    }

    /// 고정 휴식(점심 등) 시작 5분 전에 한 번 예고. (윈도우 밖에서만, 하루 1회, 자정 리셋)
    private func handleScheduledRestPrealert() {
        guard settings.scheduledRestEnabled, phase != .scheduledRest else { return }
        let now = Date()
        let day = Self.dayKey(now)
        if day != restPrealertDay {
            restPrealertDay = day
            restPrealertFired = false
        }
        guard !restPrealertFired else { return }
        let until = settings.secondsUntilScheduledRestStart(now)
        guard until > 0, until <= 5 * 60 else { return }
        restPrealertFired = true
        let label = settings.scheduledRestLabel.isEmpty ? "예약 휴식" : settings.scheduledRestLabel
        let mins = max(1, Int((until / 60).rounded(.up)))
        overlay.showScheduledRestToast(title: "곧 \(label)이에요", subtitle: "\(mins)분 뒤 시작해요")
        Log.event("예약 휴식 사전 예고 (\(mins)분 전)")
    }

    /// 하루 마무리 알림. 마칠 시각 30/15/0분 전에 한 번씩 토스트(강제 종료는 안 함).
    /// 각 단계는 하루 1회만, 자정에 리셋. 너무 늦게 켜면(2분 grace 초과) 지난 단계는 안 쏜다.
    private func handleShutdown() {
        guard settings.shutdownEnabled else { return }
        let now = Date()
        let day = Self.dayKey(now)
        if day != shutdownFiredDay {
            shutdownFiredDay = day
            shutdownFiredStages = []
        }
        let m = AppSettings.minutesOfDay(now)
        for offset in ScheduleMath.dueShutdownStages(nowMinutes: m, shutdownTime: settings.shutdownTime, fired: shutdownFiredStages) {
            shutdownFiredStages.insert(offset)
            fireShutdownStage(offset)
            Log.event("하루 마무리 알림 (\(offset == 0 ? "도래" : "\(offset)분 전"))")
        }
    }

    private func fireShutdownStage(_ offset: Int) {
        let h = settings.shutdownTime / 60, mm = settings.shutdownTime % 60
        let timeStr = String(format: "%02d:%02d", h, mm)
        switch offset {
        case 30:
            overlay.showShutdownToast(title: "오늘 일 마무리 30분 전이에요",
                                      subtitle: "\(timeStr)에 마쳐요. 슬슬 준비하세요", stop: false)
        case 15:
            overlay.showShutdownToast(title: "오늘 일 마무리 15분 전이에요",
                                      subtitle: "\(timeStr)에 마쳐요. 하던 걸 정리하세요", stop: false)
        default:
            let t = SessionStore.shared.today
            overlay.showShutdownToast(title: "오늘 일은 여기까지예요 ☕",
                                      subtitle: "오늘 \(t.sessions)회 · \(SessionStore.hm(t.minutes)) 집중했어요. 수고했어요",
                                      stop: true)
        }
    }

    private static func dayKey(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0, mo = c.month ?? 0, d = c.day ?? 0
        return y * 10000 + mo * 100 + d
    }

    /// "오늘은 그만" — 오늘까지만 Fika 를 조용히(일시정지). 날이 바뀐 뒤 복귀하면 스스로 재개한다(A-4).
    func quietForToday() {
        if phase != .paused { togglePause() }   // togglePause가 quietDay를 지우므로 반드시 그 뒤에 설정
        quietDay = Self.dayKey(Date())
    }

    /// "오늘은 그만"으로 일시정지된 상태에서 날이 바뀌고 사용자가 실제로 돌아오면(최근 입력) 자동 재개한다.
    /// 자정에 곧장 깨우면 밤새 휴식 오버레이가 뜨므로, 복귀(유휴 60초 미만)를 감지했을 때만 재개한다.
    private func handleQuietForTodayResume() {
        guard let day = quietDay, Self.dayKey(Date()) != day else { return }
        guard SystemIdle.seconds() < 60 else { return }
        quietDay = nil
        startWork()                                   // 새 날 → 작업 사이클을 새로 시작(일시정지 해제)
        overlay.showStartToast()
        Log.event("오늘은 그만 → 다음날 복귀 감지, 자동 재개")
    }

    /// 고정 휴식 시간대(예: 점심) 처리. 진입/유지/이탈을 처리했으면 true 를 돌려 평소 로직을 건너뛴다.
    /// 절대 시각 기반이라 sleep/wake 보정이 따로 필요 없다(깨어나면 "지금 시각이 윈도우 안인가"만 본다).
    private func handleScheduledRest() -> Bool {
        let inWindow = settings.isWithinScheduledRest(Date())
        if phase == .scheduledRest {
            if inWindow {
                remaining = settings.scheduledRestSecondsLeft(Date())   // 윈도우 끝까지 남은 시간
                refreshPresentation()
                return true
            }
            Log.event("예약 휴식 종료 → 작업 시작")
            startWorkFromBreak()                                        // 작업 새로 시작 + 시작 토스트
            return true
        }
        if inWindow {
            enterScheduledRest()
            return true
        }
        return false
    }

    private func enterScheduledRest() {
        phase = .scheduledRest
        isAway = false
        isLongBreak = false
        remaining = settings.scheduledRestSecondsLeft(Date())
        phaseDuration = max(settings.scheduledRestDurationSeconds, 1)
        overlay.hideWarning()
        let label = settings.scheduledRestLabel.isEmpty ? "예약 휴식" : settings.scheduledRestLabel
        let endStr = String(format: "%02d:%02d", (settings.scheduledRestEnd / 60) % 24, settings.scheduledRestEnd % 60)
        overlay.showScheduledRestToast(title: label, subtitle: "\(endStr)까지 쉬어요")
        refreshPresentation()                                          // 화면은 덮지 않음(가벼운 모드)
        Log.event("예약 휴식 진입 (\(settings.scheduledRestLabel))")
    }

    /// 작업/휴식 중일 때, 곧 올 고정 휴식까지 남은 시간 안내 문자열(설정 켜졌고 6시간 이내일 때만).
    var scheduledRestUpcoming: String? {
        guard settings.scheduledRestEnabled, phase != .scheduledRest, phase != .paused else { return nil }
        let left = settings.secondsUntilScheduledRestStart(Date())
        guard left <= 6 * 3600 else { return nil }
        let label = settings.scheduledRestLabel.isEmpty ? "예약 휴식" : settings.scheduledRestLabel
        return "\(label)까지 \(Self.hmShort(left))"
    }

    static func hmShort(_ t: TimeInterval) -> String {
        let m = max(0, Int(t / 60))
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }

    /// 작업 중 주기적으로 동작 알림(마이크로 브레이크)을 띄운다.
    /// 곧 휴식 예고 구간엔 띄우지 않는다 (곧 진짜 휴식이므로).
    private func handleMicroBreak() {
        guard settings.microBreakEnabled, phase == .working, !isAway, !isWarning else { return }
        if Date() >= nextMicroBreak {
            if let tip = settings.stretchTips.randomElement(), !tip.isEmpty {
                overlay.showStretchToast(tip)
                Log.debug("마이크로 브레이크: \(tip)")
            }
            nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
        }
    }

    /// 작업 중 주기적으로 "휴식까지 N분 남았어요" 토스트를 띄운다.
    /// 메뉴바 시간 표시와 무관한 별도 토글. 동작 알림 토스트가 떠 있으면 겹치지 않게 양보한다.
    /// 발화 시점을 "휴식까지 남은 시간"의 주기 배수(…,15,10,5분)에 정렬해, 마지막 알림이
    /// 휴식 직전에 깔끔하게 떨어지게 한다(작업 시작 기준이면 작업 시간에 따라 어긋났음).
    private func handleTimeNotice() {
        guard settings.timeNoticeEnabled, phase == .working, !isAway, !isWarning else { return }
        let period = settings.timeNoticeMinutes * 60
        guard period > 0, timeNoticeBucket >= 1 else { return }
        guard remaining <= Double(timeNoticeBucket) * period else { return }   // 다음 정렬 지점 도달 전
        if overlay.isToastVisible { return }                                   // 겹침 방지: 양보(버킷 유지, 다음 틱 재시도)
        overlay.showTimeNotice()
        // 다음 목표로 한 단계. 슬립 복귀 등으로 여러 경계를 건너뛰었으면 따라잡되 토스트는 한 번만.
        var k = timeNoticeBucket - 1
        while k >= 1, remaining <= Double(k) * period { k -= 1 }
        timeNoticeBucket = max(0, k)
        Log.debug("남은 시간 알림: \(menuTimeString) (다음 \(timeNoticeBucket)단계)")
    }

    /// 카운트다운을 닫는 마지막 알림. 휴식 직전(예고 구간 안이라도) 한 번 "곧 휴식이에요".
    /// 주기 최소가 5분이라 정렬 알림은 …10,5분에서 끝난다 → 마지막 "0분"에 해당하는 알림을 여기서 채운다.
    private func handleFinalTimeNotice() {
        guard settings.timeNoticeEnabled, phase == .working, !isAway else { return }
        guard !timeNoticeFinalFired, remaining > 0, remaining <= 30 else { return }   // 휴식 30초 전 한 번
        if overlay.isToastVisible { return }                                          // 겹침 방지: 다음 틱 재시도
        overlay.showTimeNotice(final: true)
        timeNoticeFinalFired = true
        Log.debug("남은 시간 알림: 곧 휴식(마지막)")
    }

    /// "남은 시간 알림"의 목표 단계를 남은 시간 기준으로 다시 잡는다.
    /// 가장 큰 주기 배수(단, 남은 시간보다 작은)부터 시작 → 정확히 배수면 한 칸 내려 즉시 발화를 막는다.
    private func resetTimeNoticeBucket(forRemaining seconds: Double) {
        timeNoticeFinalFired = false                                           // 새 작업 세션 → 마지막 알림도 리셋
        timeNoticeBucket = ScheduleMath.timeNoticeBucket(remaining: seconds, period: settings.timeNoticeMinutes * 60)
    }

    /// 휴식이 끝났지만 사용자가 아직 안 돌아온 상태.
    /// 입력이 감지되면(유휴 시간이 짧아지면) 그제서야 작업을 시작한다.
    /// → 자리를 비운 동안 작업 시간이 헛돌지 않는다.
    private func handleBreakHold() {
        if SystemIdle.seconds() < 2 {
            Log.debug("복귀 감지 → 작업 시작 (breakHold 해제)")
            startWorkFromBreak()
        }
    }

    /// 자리 비움(유휴) 처리. 작업 중에만 동작한다.
    /// - 임계값(idleThreshold) 이상 입력이 없으면 자리 비움으로 보고 작업 카운트다운을 동결한다.
    /// - 복귀 시: 비운 시간이 **휴식 시간(breakMinutes) 이상**이면 충분히 쉰 셈이라 사이클을 리셋하고,
    ///   미만이면 동결만 풀고 남은 시간을 이어간다. (sleep 복귀와 같은 규칙 — 잠깐 자리 비운 걸로
    ///   세션을 통째로 날리지 않는다. B-4)
    private func handleIdle() {
        guard phase == .working else {
            if isAway { isAway = false }
            return
        }
        let idle = SystemIdle.seconds()
        let threshold = settings.idleThresholdMinutes * 60
        if idle >= threshold {
            if !isAway {
                isAway = true
                awayStart = Date().addingTimeInterval(-idle)   // 실제로 입력이 끊긴 시점
                Log.debug("자리 비움 감지 (유휴 \(Int(idle))s)")
            }
            phaseEnd = phaseEnd.addingTimeInterval(1)           // 남은 시간 동결
            nextMicroBreak = nextMicroBreak.addingTimeInterval(1)  // 동결 중엔 동작 알림도 함께 밀어 복귀 즉시 발화 방지
        } else if isAway {
            isAway = false
            let awayFor = Date().timeIntervalSince(awayStart)
            if awayFor >= settings.breakMinutes * 60 {
                Log.debug("복귀 (자리 비움 \(Int(awayFor))s ≥ 휴식) → 작업 리셋")
                startWork()                                    // 충분히 쉰 셈 → 사이클 리셋
            } else {
                Log.debug("복귀 (자리 비움 \(Int(awayFor))s < 휴식) → 남은 시간 이어감")
                // 동결 해제만: phaseEnd는 이미 남은 시간을 보존하도록 밀려 있어 그대로 이어간다.
            }
        }
    }

    // MARK: - Sleep / Wake

    /// 시스템 sleep/wake는 **로그로만** 남긴다(진단용). 시간 보정은 타이머를 죽이지 않고
    /// tick()의 공백(gap) 감지로 처리한다(`handleLongGap`).
    /// → wake 알림을 놓쳐도(dark wake·빠른 sleep/wake 반복·알림 유실) 타이머가 계속 살아 있어
    ///   앱이 조용히 멈추지 않는다. (예전엔 willSleep에서 타이머를 죽여 wake를 놓치면 앱 전체가 침묵했다)
    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                Log.event("시스템 sleep (phase=\(self.phase), 남은 \(Int(self.remaining))s)")
            }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }   // 깨자마자 gap 보정을 앞당김(다음 tick을 기다리지 않음)
        }
    }

    /// tick 사이의 큰 공백(주로 시스템 sleep)을 보정한다. wake 알림이 아니라 "직전 tick과의 시간 차"로 판단.
    /// - 휴식(휴식/복귀대기): 자리를 뜨는 시간이므로 실제 시간이 흘러야 한다 → phaseEnd 그대로, 남은 시간만 재계산.
    /// - 작업: 잔 시간을 작업으로 치지 않는다. 휴식 시간 이상이면 충분히 쉰 셈이라 사이클 리셋(`idleResetEnabled`),
    ///   그보다 짧으면 공백만큼 phaseEnd를 밀어 남은 시간을 보존(안 밀면 깨자마자 휴식으로 떨어짐).
    /// - 고정 휴식: 절대 시각 기반이라 아무것도 안 해도 곧이어 `handleScheduledRest()`가 처리한다.
    private func handleLongGap(_ gap: TimeInterval) {
        switch phase {
        case .breaking, .breakHold:
            remaining = max(0, phaseEnd.timeIntervalSinceNow)
            Log.event("긴 공백 \(Int(gap))s (휴식) → 실제 시간 반영, 남은 \(Int(remaining))s")
        case .working:
            if settings.idleResetEnabled && gap >= settings.breakMinutes * 60 {
                isAway = false
                startWork()
                Log.event("긴 공백 \(Int(gap))s → 작업 리셋")
            } else {
                phaseEnd = phaseEnd.addingTimeInterval(gap)
                remaining = max(0, phaseEnd.timeIntervalSinceNow)
                nextMicroBreak = nextMicroBreak.addingTimeInterval(gap)   // A-6: 작업 진행과 함께 밀어 복귀 즉시 발화 방지
                Log.event("긴 공백 \(Int(gap))s → 남은 시간 보존")
            }
        case .scheduledRest, .paused:
            break
        }
        refreshPresentation()
    }

    private func refreshPresentation() {
        if phase == .breaking || phase == .breakHold {
            overlay.showBreak(style: settings.breakStyle)
        } else {
            overlay.hideBreak()
        }
        if isWarning {
            overlay.showWarning()
        } else {
            overlay.hideWarning()
        }
    }

    // MARK: - 전환

    private func startWork() {
        phase = .working
        isLongBreak = false
        workedSeconds = 0
        setRemaining(settings.workMinutes * 60)
        nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
        resetTimeNoticeBucket(forRemaining: settings.workMinutes * 60)
        Log.debug("작업 시작 \(Int(settings.workMinutes))분")
    }

    /// 휴식을 마치고 작업으로 돌아갈 때. 작업 시작 토스트를 잠깐 띄운다.
    private func startWorkFromBreak() {
        startWork()
        refreshPresentation()      // 휴식 오버레이 내림
        overlay.showStartToast()
    }

    private func enterBreak() {
        // 계획 길이(phaseDuration)가 아니라 이번 세션 실제 집중분을 기록한다(B-1·B-2).
        // 60초 미만(수동 "지금 휴식"·시작 직후 등)은 가짜 세션이므로 기록·카운트 제외.
        let focus = workedSeconds
        workedSeconds = 0
        if focus >= 60 {
            SessionStore.shared.record(minutes: focus / 60, at: Date())
            completedWork += 1
        }
        isLongBreak = settings.longBreakEnabled
            && settings.cyclesBeforeLongBreak > 0
            && completedWork % settings.cyclesBeforeLongBreak == 0
        phase = .breaking
        setRemaining((isLongBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60)
        Sound.play(.breakStart, enabled: settings.soundEnabled)
        refreshPresentation()
        Log.debug("휴식 진입 \(isLongBreak ? "긴" : "짧은") (집중 \(Int(focus))s, 완료 세션 \(completedWork))")
    }

    private func endBreak() {
        Sound.play(.breakEnd, enabled: settings.soundEnabled)
        if settings.holdBreakUntilReturn {
            enterBreakHold()      // 돌아올 때까지 작업 시작을 미룬다
            refreshPresentation()
        } else {
            startWorkFromBreak()
        }
    }

    private func enterBreakHold() {
        phase = .breakHold
        isLongBreak = false
        remaining = 0
        phaseDuration = 1
        Log.debug("휴식 종료 → 복귀 대기(breakHold)")
    }

    private func setRemaining(_ t: TimeInterval) {
        remaining = t
        phaseDuration = max(t, 1)
        phaseEnd = Date().addingTimeInterval(t)
    }

    // MARK: - 사용자 동작

    func togglePause() {
        quietDay = nil                          // 수동 토글은 "오늘은 그만" 상태를 해제(자동 재개 대상 아님)
        if phase == .paused {
            phase = phaseBeforePause
            phaseEnd = Date().addingTimeInterval(pausedRemaining)
            remaining = pausedRemaining
            nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)  // A-6: 재개 기준으로 다시 잡음(즉시 발화 방지)
        } else {
            phaseBeforePause = phase
            pausedRemaining = remaining
            phase = .paused
        }
        refreshPresentation()
    }

    /// 이번 작업 세션에 한해 "N분 뒤 휴식"으로 남은 시간을 덮어씀.
    /// (설정의 영구 작업 시간은 그대로 둠)
    func setTimeUntilBreak(_ minutes: Double) {
        guard phase == .working else { return }
        isAway = false
        setRemaining(minutes * 60)
        resetTimeNoticeBucket(forRemaining: minutes * 60)   // 바뀐 남은 시간에 알림 단계도 재정렬
        refreshPresentation()
    }

    /// 작업 세션을 처음부터(설정한 작업 시간) 다시 시작한다. (집중 못 했을 때 수동 리셋)
    func restartWork() {
        guard phase == .working else { return }
        isAway = false
        workedSeconds = 0                                   // 못 집중한 세션 버림 → 기록 안 함
        setRemaining(settings.workMinutes * 60)
        nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
        resetTimeNoticeBucket(forRemaining: settings.workMinutes * 60)
        refreshPresentation()
        Log.debug("작업 다시 시작 (수동)")
    }

    /// 지금 바로 휴식 시작 (작업 중일 때).
    func breakNow() {
        guard phase == .working else { return }
        setRemaining(0)
        enterBreak()
    }

    /// 휴식 건너뛰고 다음 작업 시작. (복귀 대기 중이면 바로 작업 시작)
    func skipBreak() {
        guard phase == .breaking || phase == .breakHold else { return }
        startWorkFromBreak()
    }

    /// 5분(설정값) 연기.
    /// - 예고 중: 작업 시간을 그만큼 늘림.
    /// - 휴식 중: 휴식을 끝내고 그만큼 더 작업한 뒤 다시 휴식.
    func snooze() {
        let extra = settings.snoozeMinutes * 60
        switch phase {
        case .working:
            setRemaining(remaining + extra)
        case .breaking:
            phase = .working
            isLongBreak = false
            setRemaining(extra)
        case .breakHold, .paused, .scheduledRest:
            break
        }
        // 연기로 남은 시간이 바뀌었으니 알림 스케줄을 새 남은 시간에 맞춰 재정렬한다.
        // (안 하면: 연장 구간에 남은 시간 알림이 안 오거나, 마지막 "곧 휴식"이 다시 안 뜨거나,
        //  마이크로 브레이크가 옛 기준점이라 복귀 즉시 뜬다.)
        if phase == .working {
            resetTimeNoticeBucket(forRemaining: remaining)   // timeNoticeFinalFired 도 함께 리셋됨
            nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
        }
        refreshPresentation()
    }

    // MARK: - 알림 테스트 (설정 패널에서 즉석 확인용 — 멀티 모니터에서 "어느 화면에 뜨는지"도 확인)

    func testStretchAlert() {
        let tip = settings.stretchTips.filter { !$0.isEmpty }.randomElement() ?? "발목을 위아래로 까딱까딱 (혈액순환!)"
        overlay.showStretchToast(tip)
    }
    func testTimeNoticeAlert() { overlay.showTimeNotice() }
    func testShutdownAlert() {
        overlay.showShutdownToast(title: "오늘 일은 여기까지예요 ☕", subtitle: "테스트 알림이에요", stop: false)
    }
}
