import Foundation
import Combine

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

/// 사용자 설정. UserDefaults 에 자동 저장됩니다.
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

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
    @Published var microBreakEnabled: Bool        { didSet { d.set(microBreakEnabled, forKey: "microBreakEnabled") } }
    /// 마이크로 브레이크 주기(분)
    @Published var microBreakMinutes: Double      { didSet { d.set(microBreakMinutes, forKey: "microBreakMinutes") } }

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
        breakStyle = .fullscreen
        iconTheme = .coffee
        showMenuBarTime = true
        soundEnabled = true
        idleResetEnabled = true
        holdBreakUntilReturn = true
        idleThresholdMinutes = 5
    }
}
