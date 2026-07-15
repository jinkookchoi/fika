import Foundation

/// 잠깐 떴다 사라지는 토스트 알림 1건. 발화처(BreakEngine)는 이것만 만들어
/// `OverlayController.post()`에 넘긴다 — 창 생성·타이머·로그 기록·소리 같은
/// "어떻게 보여줄지"는 전부 post() 한 곳에서 처리한다.
/// 새 알림 추가 = 여기 case 추가 + post()의 switch 채우기 (컴파일러가 누락을 잡아줌).
/// (예고 배너는 알림이 아니라 상태 표시라 이 파이프라인 밖 — showWarning 유지)
enum Notice {
    case start                                                   // 작업 시작 격려
    case stretch(tip: String)                                    // 동작 알림(마이크로 브레이크)
    case timeNotice(final: Bool)                                 // 휴식까지 남은 시간
    case shutdown(title: String, subtitle: String, stop: Bool)   // 하루 마무리 (stop = "오늘은 그만" 버튼)
    case scheduledRest(title: String, subtitle: String)          // 고정 휴식 예고/진입

    /// 알림 이력(NotificationLog)의 분류 이름.
    var logCategory: String {
        switch self {
        case .start:         return "시작"
        case .stretch:       return "동작"
        case .timeNotice:    return "남은시간"
        case .shutdown:      return "마무리"
        case .scheduledRest: return "고정휴식"
        }
    }

    /// 화면 표시 시간(초). timeNotice 는 사용자 설정값이라 여기서 못 정한다(nil → post()에서 결정).
    var duration: TimeInterval? {
        switch self {
        case .start:                    return 5
        case .stretch:                  return 10
        case .timeNotice:               return nil
        case .shutdown(_, _, let stop): return stop ? 12 : 6
        case .scheduledRest:            return 6
        }
    }
}
