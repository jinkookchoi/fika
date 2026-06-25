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
}
