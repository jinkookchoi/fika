import Foundation
import Combine
import FikaCore

/// 메뉴바 아이콘 테마.
enum IconTheme: String, CaseIterable, Identifiable {
    case coffee   // 커피 잔 애니메이션 (작업하면 줄고 휴식하면 채워짐)
    case emoji    // 컬러 이모지 (귀여움)
    case symbol   // SF 심볼 (단색·미니멀, 다크/라이트 자동 적응)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .coffee: return "커피 잔 (애니메이션)"
        case .emoji:  return "이모지 (컬러)"
        case .symbol: return "기호 (단색·미니멀)"
        }
    }
}

/// 휴식을 알리는 방식.
enum BreakStyle: String, CaseIterable, Identifiable {
    case fullscreen   // 전체화면을 덮어 강제로 멈추게 함
    case soft         // 화면 가장자리 글로우 + 작은 카드 (클릭은 통과)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fullscreen: return "전체화면 덮기"
        case .soft:       return "부드러운 효과"
        }
    }
    var detail: String {
        switch self {
        case .fullscreen: return "휴식 동안 화면을 덮어 작업을 멈추게 합니다."
        case .soft:       return "가장자리 효과와 작은 카드로 알립니다. 화면 아래는 계속 사용 가능합니다."
        }
    }
}

/// 남은 시간 알림 토스트가 뜨는 위치.
enum ToastPosition: String, CaseIterable, Identifiable {
    case topCenter, center, bottomRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .topCenter:   return "상단 중앙"
        case .center:      return "화면 중앙"
        case .bottomRight: return "우하단"
        }
    }
}

/// 토스트 등장 모션.
enum ToastMotion: String, CaseIterable, Identifiable {
    case spring, slide, bounce
    var id: String { rawValue }
    var label: String {
        switch self {
        case .spring: return "스프링"
        case .slide:  return "슬라이드"
        case .bounce: return "바운스"
        }
    }
}

/// 남은 시간 알림 소리. 지금은 없음/차임. (향후 음성(TTS) 확장 여지를 위해 enum 으로 둠)
enum NoticeSound: String, CaseIterable, Identifiable {
    case none, chime
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:  return "없음"
        case .chime: return "차임"
        }
    }
}

/// 사용자 설정. UserDefaults 에 자동 저장됩니다.
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    /// 주기류 설정(알림 주기 등)이 바뀌면 엔진이 스케줄을 재정렬하도록 알리는 훅(A-7/§5-3).
    /// 엔진이 init에서 구독한다. UserDefaults 저장과 별개.
    var onScheduleChange: (() -> Void)?

    /// 앉아서 일하며 할 수 있는 기본 동작 문구. (사용자가 설정에서 편집 가능)
    static let defaultStretchTips = [
        "고개를 천천히 좌우로 기울여요 (각 5초)",
        "어깨를 으쓱 올렸다가 툭 내려요 (3번)",
        "먼 곳을 20초 바라봐요 — 눈도 쉬어야죠",
        "손목을 천천히 돌려요 (양쪽 5바퀴씩)",
        "의자에 기대 등을 쭉 펴고 가슴을 열어요",
        "발목을 위아래로 까딱까딱 (혈액순환!)",
        "코로 깊게 들이쉬고, 천천히 내쉬어요 (3번)",
        "고개를 크게 천천히 한 바퀴 돌려요",
        "손가락을 쫙 폈다 주먹 쥐기 (10번)",
        "잠깐 일어나서 온몸을 쭉 펴요",
    ]

    @Published var workMinutes: Double            { didSet { d.set(workMinutes, forKey: "workMinutes") } }
    @Published var breakMinutes: Double           { didSet { d.set(breakMinutes, forKey: "breakMinutes") } }
    @Published var longBreakEnabled: Bool         { didSet { d.set(longBreakEnabled, forKey: "longBreakEnabled") } }
    @Published var longBreakMinutes: Double       { didSet { d.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published var cyclesBeforeLongBreak: Int     { didSet { d.set(cyclesBeforeLongBreak, forKey: "cyclesBeforeLongBreak") } }
    @Published var warningSeconds: Double         { didSet { d.set(warningSeconds, forKey: "warningSeconds") } }
    @Published var snoozeMinutes: Double          { didSet { d.set(snoozeMinutes, forKey: "snoozeMinutes") } }
    /// 작업 세션당 연기 횟수 제한 — 소진되면 연기 버튼이 사라지고 반드시 쉬게 된다
    @Published var snoozeLimitEnabled: Bool       { didSet { d.set(snoozeLimitEnabled, forKey: "snoozeLimitEnabled") } }
    @Published var snoozeMaxCount: Double         { didSet { d.set(snoozeMaxCount, forKey: "snoozeMaxCount") } }
    @Published var breakStyle: BreakStyle         { didSet { d.set(breakStyle.rawValue, forKey: "breakStyle") } }
    @Published var iconTheme: IconTheme           { didSet { d.set(iconTheme.rawValue, forKey: "iconTheme") } }
    @Published var showMenuBarTime: Bool          { didSet { d.set(showMenuBarTime, forKey: "showMenuBarTime") } }
    @Published var soundEnabled: Bool             { didSet { d.set(soundEnabled, forKey: "soundEnabled") } }
    @Published var idleResetEnabled: Bool         { didSet { d.set(idleResetEnabled, forKey: "idleResetEnabled") } }
    @Published var holdBreakUntilReturn: Bool     { didSet { d.set(holdBreakUntilReturn, forKey: "holdBreakUntilReturn") } }
    @Published var idleThresholdMinutes: Double   { didSet { d.set(idleThresholdMinutes, forKey: "idleThresholdMinutes") } }
    @Published var launchAtLogin: Bool            { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); LoginItem.set(launchAtLogin) } }
    @Published var debugMode: Bool                { didSet { d.set(debugMode, forKey: "debugMode"); Log.debugEnabled = debugMode } }
    /// 휴식·마이크로 알림에 보여줄 동작 문구 목록
    @Published var stretchTips: [String]          { didSet { d.set(stretchTips, forKey: "stretchTips") } }
    /// 작업 중 주기적으로 동작 알림(마이크로 브레이크)을 띄울지
    @Published var microBreakEnabled: Bool        { didSet { d.set(microBreakEnabled, forKey: "microBreakEnabled"); onScheduleChange?() } }
    /// 마이크로 브레이크 주기(분)
    @Published var microBreakMinutes: Double      { didSet { d.set(microBreakMinutes, forKey: "microBreakMinutes"); onScheduleChange?() } }
    /// 작업 중 주기적으로 "남은 시간" 토스트를 띄울지 (메뉴바 시간 표시와 무관한 별도 토글)
    @Published var timeNoticeEnabled: Bool        { didSet { d.set(timeNoticeEnabled, forKey: "timeNoticeEnabled"); onScheduleChange?() } }
    /// 남은 시간 알림 주기(분)
    @Published var timeNoticeMinutes: Double      { didSet { d.set(timeNoticeMinutes, forKey: "timeNoticeMinutes"); onScheduleChange?() } }
    // 남은 시간 알림 겉모습/동작 (각각 독립 설정)
    @Published var timeNoticePosition: ToastPosition { didSet { d.set(timeNoticePosition.rawValue, forKey: "timeNoticePosition") } }
    @Published var timeNoticeHero: Bool           { didSet { d.set(timeNoticeHero, forKey: "timeNoticeHero") } }
    @Published var timeNoticeWarm: Bool           { didSet { d.set(timeNoticeWarm, forKey: "timeNoticeWarm") } }
    @Published var timeNoticeBig: Bool            { didSet { d.set(timeNoticeBig, forKey: "timeNoticeBig") } }
    @Published var timeNoticeMotion: ToastMotion  { didSet { d.set(timeNoticeMotion.rawValue, forKey: "timeNoticeMotion") } }
    @Published var timeNoticePulse: Bool          { didSet { d.set(timeNoticePulse, forKey: "timeNoticePulse") } }
    @Published var timeNoticeDuration: Double     { didSet { d.set(timeNoticeDuration, forKey: "timeNoticeDuration") } }
    @Published var timeNoticeSound: NoticeSound   { didSet { d.set(timeNoticeSound.rawValue, forKey: "timeNoticeSound") } }
    /// 고정 휴식 시간대 사용 (예: 점심 11:30~13:00엔 무조건 쉼)
    @Published var scheduledRestEnabled: Bool     { didSet { d.set(scheduledRestEnabled, forKey: "scheduledRestEnabled") } }
    /// 시작/끝 (자정 기준 분). 기본 11:30~13:00
    @Published var scheduledRestStart: Int        { didSet { d.set(scheduledRestStart, forKey: "scheduledRestStart") } }
    @Published var scheduledRestEnd: Int          { didSet { d.set(scheduledRestEnd, forKey: "scheduledRestEnd") } }
    /// 시간대 이름 (메뉴바·패널 표시용)
    @Published var scheduledRestLabel: String     { didSet { d.set(scheduledRestLabel, forKey: "scheduledRestLabel") } }
    /// 하루 마무리 알림 (마칠 시각 30/15/0분 전에 알림). 강제 종료는 하지 않음.
    @Published var shutdownEnabled: Bool          { didSet { d.set(shutdownEnabled, forKey: "shutdownEnabled") } }
    /// 마칠 시각 (자정 기준 분). 기본 18:00
    @Published var shutdownTime: Int              { didSet { d.set(shutdownTime, forKey: "shutdownTime") } }

    init() {
        let store = UserDefaults.standard
        func dbl(_ k: String, _ def: Double) -> Double { store.object(forKey: k) == nil ? def : store.double(forKey: k) }
        func int(_ k: String, _ def: Int) -> Int       { store.object(forKey: k) == nil ? def : store.integer(forKey: k) }
        func bool(_ k: String, _ def: Bool) -> Bool     { store.object(forKey: k) == nil ? def : store.bool(forKey: k) }

        workMinutes           = dbl("workMinutes", 50)
        breakMinutes          = dbl("breakMinutes", 10)
        longBreakEnabled      = bool("longBreakEnabled", true)
        longBreakMinutes      = dbl("longBreakMinutes", 20)
        cyclesBeforeLongBreak = int("cyclesBeforeLongBreak", 4)
        warningSeconds        = dbl("warningSeconds", 60)
        snoozeMinutes         = dbl("snoozeMinutes", 5)
        snoozeLimitEnabled    = bool("snoozeLimitEnabled", true)
        snoozeMaxCount        = dbl("snoozeMaxCount", 3)
        breakStyle            = BreakStyle(rawValue: d.string(forKey: "breakStyle") ?? "") ?? .fullscreen
        iconTheme             = IconTheme(rawValue: d.string(forKey: "iconTheme") ?? "") ?? .coffee
        showMenuBarTime       = bool("showMenuBarTime", true)
        soundEnabled          = bool("soundEnabled", true)
        idleResetEnabled      = bool("idleResetEnabled", true)
        holdBreakUntilReturn  = bool("holdBreakUntilReturn", true)
        idleThresholdMinutes  = dbl("idleThresholdMinutes", 5)
        launchAtLogin         = bool("launchAtLogin", false)
        debugMode             = bool("debugMode", false)
        let savedTips = store.array(forKey: "stretchTips") as? [String]
        stretchTips           = (savedTips?.isEmpty == false ? savedTips! : Self.defaultStretchTips)
        microBreakEnabled     = bool("microBreakEnabled", true)
        microBreakMinutes     = dbl("microBreakMinutes", 10)
        timeNoticeEnabled     = bool("timeNoticeEnabled", false)
        timeNoticeMinutes     = dbl("timeNoticeMinutes", 5)
        timeNoticePosition    = ToastPosition(rawValue: store.string(forKey: "timeNoticePosition") ?? "") ?? .topCenter
        timeNoticeHero        = bool("timeNoticeHero", true)
        timeNoticeWarm        = bool("timeNoticeWarm", false)
        timeNoticeBig         = bool("timeNoticeBig", false)
        timeNoticeMotion      = ToastMotion(rawValue: store.string(forKey: "timeNoticeMotion") ?? "") ?? .slide
        timeNoticePulse       = bool("timeNoticePulse", true)
        timeNoticeDuration    = dbl("timeNoticeDuration", 7)
        timeNoticeSound       = NoticeSound(rawValue: store.string(forKey: "timeNoticeSound") ?? "") ?? .chime
        scheduledRestEnabled  = bool("scheduledRestEnabled", false)
        scheduledRestStart    = int("scheduledRestStart", 11 * 60 + 30)
        scheduledRestEnd      = int("scheduledRestEnd", 13 * 60)
        scheduledRestLabel    = store.string(forKey: "scheduledRestLabel") ?? "점심 휴식"
        shutdownEnabled       = bool("shutdownEnabled", false)
        shutdownTime          = int("shutdownTime", 18 * 60)
        Log.debugEnabled = debugMode
    }

    /// 시간/알림 관련 값을 기본값으로 되돌린다. (자동 실행 상태는 건드리지 않음)
    func resetToDefaults() {
        workMinutes = 50
        breakMinutes = 10
        longBreakEnabled = true
        longBreakMinutes = 20
        cyclesBeforeLongBreak = 4
        warningSeconds = 60
        snoozeMinutes = 5
        snoozeLimitEnabled = true
        snoozeMaxCount = 3
        breakStyle = .fullscreen
        iconTheme = .coffee
        showMenuBarTime = true
        soundEnabled = true
        idleResetEnabled = true
        holdBreakUntilReturn = true
        idleThresholdMinutes = 5
        scheduledRestEnabled = false
        scheduledRestStart = 11 * 60 + 30
        scheduledRestEnd = 13 * 60
        scheduledRestLabel = "점심 휴식"
        shutdownEnabled = false
        shutdownTime = 18 * 60
    }

    // MARK: - 고정 휴식 시간대 계산 (자정 기준 분/초)

    static func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h: Int = c.hour ?? 0
        let m: Int = c.minute ?? 0
        return h * 60 + m
    }
    private static func secondsOfDay(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h: Int = c.hour ?? 0
        let m: Int = c.minute ?? 0
        let s: Int = c.second ?? 0
        return Double(h * 3600 + m * 60 + s)
    }
    /// 지금이 고정 휴식 시간대 안인지.
    func isWithinScheduledRest(_ date: Date) -> Bool {
        guard scheduledRestEnabled else { return false }
        return ScheduleMath.isWithinRest(nowMinutes: Self.minutesOfDay(date),
                                         start: scheduledRestStart, end: scheduledRestEnd)
    }
    /// 시간대 전체 길이(초). 진행 링용.
    var scheduledRestDurationSeconds: TimeInterval {
        var d = Double(scheduledRestEnd - scheduledRestStart) * 60
        if d <= 0 { d += 24 * 3600 }
        return d
    }
    /// 시간대 끝까지 남은 초.
    func scheduledRestSecondsLeft(_ date: Date) -> TimeInterval {
        let now = Self.secondsOfDay(date)
        var end = Double(scheduledRestEnd) * 60
        if end <= now { end += 24 * 3600 }
        return max(0, end - now)
    }
    /// 다음 시간대 시작까지 남은 초.
    func secondsUntilScheduledRestStart(_ date: Date) -> TimeInterval {
        let now = Self.secondsOfDay(date)
        var start = Double(scheduledRestStart) * 60
        if start <= now { start += 24 * 3600 }
        return start - now
    }
}
