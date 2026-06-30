import SwiftUI
import AppKit

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
    private var timer: Timer?
    /// 시스템 sleep 진입 시각 (wake 때 얼마나 잤는지 계산용)
    private var sleepAt: Date?
    /// 다음 마이크로 브레이크(작업 중 동작 알림) 예정 시각
    private var nextMicroBreak: Date = .distantFuture
    /// 다음 "남은 시간 알림" 토스트 예정 시각
    private var nextTimeNotice: Date = .distantFuture
    /// 하루 마무리 알림: 오늘 이미 쏜 단계(30/15/0)와 그 날짜키 (자정에 리셋)
    private var shutdownFiredStages: Set<Int> = []
    private var shutdownFiredDay = -1
    private lazy var overlay = OverlayController(engine: self)

    /// 메뉴바 호버 팁 표시/숨김 (AppDelegate 의 트래킹에서 호출).
    func showMenuHoverTip(near anchor: NSRect) { overlay.showHoverTip(near: anchor) }
    func hideMenuHoverTip() { overlay.hideHoverTip() }

    private init() {
        startWork()
        startTimer()
        observeSleepWake()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
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
        if remaining <= 0 {
            switch phase {
            case .working:  enterBreak()
            case .breaking: endBreak()
            case .breakHold, .paused, .scheduledRest: break
            }
        }
        handleMicroBreak()
        handleTimeNotice()
        handleShutdown()
        refreshPresentation()
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
        for offset in [30, 15, 0] {
            let target = settings.shutdownTime - offset
            guard target >= 0, !shutdownFiredStages.contains(offset), m >= target, m < target + 2 else { continue }
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
            overlay.showShutdownToast(title: "슬슬 마무리할 시간이에요", subtitle: "\(timeStr)에 오늘 일을 마쳐요", stop: false)
        case 15:
            overlay.showShutdownToast(title: "15분 남았어요", subtitle: "하던 걸 정리해 보세요", stop: false)
        default:
            let t = SessionStore.shared.today
            overlay.showShutdownToast(title: "오늘은 여기까지 ☕",
                                      subtitle: "오늘 \(t.sessions)회 · \(SessionStore.hm(t.minutes)) 집중했어요",
                                      stop: true)
        }
    }

    private static func dayKey(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0, mo = c.month ?? 0, d = c.day ?? 0
        return y * 10000 + mo * 100 + d
    }

    /// "오늘은 그만" — Fika 를 조용히(일시정지). 다음 날 작업 시작 때 재개 누르면 됨.
    func quietForToday() {
        if phase != .paused { togglePause() }
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
        overlay.showScheduledRestToast(settings.scheduledRestLabel, endsAt: settings.scheduledRestEnd)
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
    private func handleTimeNotice() {
        guard settings.timeNoticeEnabled, phase == .working, !isAway, !isWarning else { return }
        guard Date() >= nextTimeNotice else { return }
        if overlay.isToastVisible {                                  // 동작 알림 등과 겹침 방지
            nextTimeNotice = Date().addingTimeInterval(20)           // 잠깐 미뤘다 다시 시도
            return
        }
        overlay.showTimeNotice()
        nextTimeNotice = Date().addingTimeInterval(settings.timeNoticeMinutes * 60)
        Log.debug("남은 시간 알림: \(menuTimeString)")
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
    /// - 임계값 이상 입력이 없으면 작업 카운트다운을 동결한다.
    /// - 복귀하면 그만큼 쉬었다고 보고 작업 세션을 처음부터 리셋한다.
    private func handleIdle() {
        guard phase == .working else {
            if isAway { isAway = false }
            return
        }
        let idle = SystemIdle.seconds()
        let threshold = settings.idleThresholdMinutes * 60
        if idle >= threshold {
            if !isAway { Log.debug("자리 비움 감지 (유휴 \(Int(idle))s)") }
            isAway = true
            phaseEnd = phaseEnd.addingTimeInterval(1)  // 한 틱만큼 미뤄 남은 시간 유지
        } else if isAway {
            isAway = false
            Log.debug("복귀 → 작업 리셋")
            startWork()                                // 휴식으로 인정 → 작업 리셋
        }
    }

    // MARK: - Sleep / Wake

    /// 노트북 닫힘(sleep)·복귀(wake)를 직접 받는다.
    /// sleep 중에는 Timer가 멈춰 `handleIdle()`이 자리 비움을 인지하지 못하므로
    /// 별도로 처리한다. (유휴 자리비움은 화면 켠 채만 커버)
    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWillSleep() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleDidWake() }
        }
    }

    private func handleWillSleep() {
        sleepAt = Date()
        timer?.invalidate()  // wake 때 보정을 마친 뒤 직접 재시작한다
        timer = nil
        Log.event("시스템 sleep (phase=\(phase), 남은 \(Int(remaining))s)")
    }

    /// 복귀 시 잔 시간만큼 보정한다.
    /// - 휴식 시간 이상 잤으면: 이미 충분히 쉰 셈 → 작업 사이클 리셋 (`idleResetEnabled` 한정)
    /// - 그보다 짧으면: 잔 시간을 작업으로 치지 않고 남은 시간을 동결해 보존
    ///   (보정이 없으면 wall-clock phaseEnd가 과거가 돼 깨자마자 휴식으로 떨어진다)
    private func handleDidWake() {
        defer { startTimer() }
        guard let sleptFrom = sleepAt, phase != .paused else { return }
        sleepAt = nil
        let slept = Date().timeIntervalSince(sleptFrom)
        if settings.idleResetEnabled && slept >= settings.breakMinutes * 60 {
            isAway = false
            startWork()
            Log.event("시스템 wake — \(Int(slept))s 잠 → 작업 리셋")
        } else {
            phaseEnd = phaseEnd.addingTimeInterval(slept)
            remaining = max(0, phaseEnd.timeIntervalSinceNow)
            Log.event("시스템 wake — \(Int(slept))s 잠 → 남은 시간 보존 (phase=\(phase))")
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
        setRemaining(settings.workMinutes * 60)
        nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
        nextTimeNotice = Date().addingTimeInterval(settings.timeNoticeMinutes * 60)
        Log.debug("작업 시작 \(Int(settings.workMinutes))분")
    }

    /// 휴식을 마치고 작업으로 돌아갈 때. 작업 시작 토스트를 잠깐 띄운다.
    private func startWorkFromBreak() {
        startWork()
        refreshPresentation()      // 휴식 오버레이 내림
        overlay.showStartToast()
    }

    private func enterBreak() {
        SessionStore.shared.record(minutes: phaseDuration / 60, at: Date())  // 직전 작업 세션 (phase 바뀌기 전)
        completedWork += 1
        isLongBreak = settings.longBreakEnabled
            && settings.cyclesBeforeLongBreak > 0
            && completedWork % settings.cyclesBeforeLongBreak == 0
        phase = .breaking
        setRemaining((isLongBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60)
        Sound.play(.breakStart, enabled: settings.soundEnabled)
        refreshPresentation()
        Log.debug("휴식 진입 \(isLongBreak ? "긴" : "짧은") (완료 세션 \(completedWork))")
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
        if phase == .paused {
            phase = phaseBeforePause
            phaseEnd = Date().addingTimeInterval(pausedRemaining)
            remaining = pausedRemaining
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
        refreshPresentation()
    }

    /// 작업 세션을 처음부터(설정한 작업 시간) 다시 시작한다. (집중 못 했을 때 수동 리셋)
    func restartWork() {
        guard phase == .working else { return }
        isAway = false
        setRemaining(settings.workMinutes * 60)
        nextMicroBreak = Date().addingTimeInterval(settings.microBreakMinutes * 60)
        nextTimeNotice = Date().addingTimeInterval(settings.timeNoticeMinutes * 60)
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
        refreshPresentation()
    }
}
