import Foundation
import Combine

/// 메뉴바 아이콘 테마.
enum IconTheme: String, CaseIterable, Identifiable {
    case emoji    // 컬러 이모지 (귀여움)
    case symbol   // SF 심볼 (단색·미니멀, 다크/라이트 자동 적응)

    var id: String { rawValue }
    var label: String {
        switch self {
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
    @Published var idleThresholdMinutes: Double   { didSet { d.set(idleThresholdMinutes, forKey: "idleThresholdMinutes") } }
    @Published var launchAtLogin: Bool            { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); LoginItem.set(launchAtLogin) } }

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
        iconTheme             = IconTheme(rawValue: d.string(forKey: "iconTheme") ?? "") ?? .emoji
        showMenuBarTime       = bool("showMenuBarTime", false)
        soundEnabled          = bool("soundEnabled", true)
        idleResetEnabled      = bool("idleResetEnabled", true)
        idleThresholdMinutes  = dbl("idleThresholdMinutes", 5)
        launchAtLogin         = bool("launchAtLogin", false)
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
        iconTheme = .emoji
        showMenuBarTime = false
        soundEnabled = true
        idleResetEnabled = true
        idleThresholdMinutes = 5
    }
}
