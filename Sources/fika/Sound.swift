import AppKit

enum Sound {
    enum Kind {
        case breakStart, breakEnd
        var systemName: String {
            switch self {
            case .breakStart: return "Submarine"
            case .breakEnd:   return "Glass"
            }
        }
    }

    static func play(_ kind: Kind, enabled: Bool) {
        guard enabled else { return }
        NSSound(named: kind.systemName)?.play()
    }

    /// 남은 시간 알림 소리. 지금은 짧은 시스템 차임. (향후 음성(TTS)은 여기 case 를 늘리면 됨)
    static func playNotice(_ sound: NoticeSound) {
        switch sound {
        case .none:  break
        case .chime: NSSound(named: "Tink")?.play()
        }
    }
}
