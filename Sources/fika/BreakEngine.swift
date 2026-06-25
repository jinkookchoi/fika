import SwiftUI
import AppKit

enum Phase {
    case working    // 작업 중
    case breaking   // 휴식 중
    case paused     // 일시정지
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
    private lazy var overlay = OverlayController(engine: self)

    private init() {
        startWork()
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
        case .working:  return isWarning ? "곧 휴식" : "작업 중"
        case .breaking: return isLongBreak ? "긴 휴식" : "휴식 중"
        case .paused:   return "일시정지"
        }
    }

    var timeString: String { Self.mmss(remaining) }

    /// 남은 시간 비율 0~1 (진행 링용)
    var progress: Double {
        phaseDuration <= 0 ? 0 : min(1, max(0, remaining / phaseDuration))
    }

    /// 단계별 색 (진행 링·강조용)
    var phaseColor: Color {
        if isAway { return .gray }
        switch phase {
        case .working:  return isWarning ? .orange : .green
        case .breaking: return isLongBreak ? .indigo : .teal
        case .paused:   return .gray
        }
    }

    /// 컬러 이모지 테마 글리프.
    var iconEmoji: String {
        if isAway { return "💤" }
        switch phase {
        case .working:  return isWarning ? "⏳" : "🌱"
        case .breaking: return isLongBreak ? "🌙" : "☕️"
        case .paused:   return "⏸️"
        }
    }

    /// SF 심볼 테마 이름.
    var iconSymbol: String {
        if isAway { return "moon.zzz.fill" }
        switch phase {
        case .working:  return isWarning ? "hourglass" : "leaf.fill"
        case .breaking: return isLongBreak ? "moon.stars.fill" : "cup.and.saucer.fill"
        case .paused:   return "pause.fill"
        }
    }

    static func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - 틱

    private func tick() {
        guard phase != .paused else { return }
        if settings.idleResetEnabled {
            handleIdle()
        } else if isAway {
            isAway = false
        }
        remaining = max(0, phaseEnd.timeIntervalSinceNow)
        if remaining <= 0 {
            switch phase {
            case .working:  enterBreak()
            case .breaking: endBreak()
            case .paused:   break
            }
        }
        refreshPresentation()
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
            isAway = true
            phaseEnd = phaseEnd.addingTimeInterval(1)  // 한 틱만큼 미뤄 남은 시간 유지
        } else if isAway {
            isAway = false
            startWork()                                // 휴식으로 인정 → 작업 리셋
        }
    }

    private func refreshPresentation() {
        if phase == .breaking {
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
    }

    private func enterBreak() {
        completedWork += 1
        isLongBreak = settings.longBreakEnabled
            && settings.cyclesBeforeLongBreak > 0
            && completedWork % settings.cyclesBeforeLongBreak == 0
        phase = .breaking
        setRemaining((isLongBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60)
        Sound.play(.breakStart, enabled: settings.soundEnabled)
        refreshPresentation()
    }

    private func endBreak() {
        Sound.play(.breakEnd, enabled: settings.soundEnabled)
        startWork()
        refreshPresentation()
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

    /// 지금 바로 휴식 시작 (작업 중일 때).
    func breakNow() {
        guard phase == .working else { return }
        setRemaining(0)
        enterBreak()
    }

    /// 휴식 건너뛰고 다음 작업 시작.
    func skipBreak() {
        guard phase == .breaking else { return }
        startWork()
        refreshPresentation()
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
        case .paused:
            break
        }
        refreshPresentation()
    }
}
