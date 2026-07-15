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
    case scheduledRest(title: String, subtitle: String, entering: Bool)   // 고정 휴식 (entering=진입, false=사전 예고)

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

    // MARK: - 겹침 정책 입력 (NoticePolicy가 판정에 사용)

    /// 우선순위 — 숫자가 작을수록 급함. 떠 있는 토스트보다 급하면 교체, 아니면 대기.
    var priority: Int {
        switch self {
        case .shutdown(_, _, true):            return 1   // 마무리 도래: 행동(버튼)을 요구
        case .scheduledRest(_, _, true):       return 2   // 고정 휴식 진입: 실제 상태 변화
        case .timeNotice(final: true):         return 3   // "곧 휴식": 미루면 의미 없음
        case .shutdown:                        return 4   // 마무리 30/15분 전
        case .scheduledRest:                   return 5   // 고정 휴식 사전 예고
        case .stretch:                         return 6   // 동작: 주기적, 다음 기회 있음
        case .start, .timeNotice:              return 7   // 가장 미루기 쉬움
        }
    }

    /// 대기 슬롯에서 살아 있을 수 있는 시간(초). 지나면 조용히 폐기 —
    /// sleep/wake나 긴 토스트에 밀려 한참 뒤에 낡은 알림이 뜨는 걸 막는다.
    var validity: TimeInterval {
        switch self {
        case .start:                    return 30
        case .stretch:                  return 120
        case .timeNotice(final: true):  return 30    // "곧 휴식"이 휴식 후에 뜨면 코미디
        case .timeNotice:               return 60
        case .shutdown(_, _, true):     return 600   // 마무리 도래는 오래 기다려서라도 보여줌
        case .shutdown:                 return 300
        case .scheduledRest(_, _, true): return 300
        case .scheduledRest:            return 120
        }
    }

    /// 예고 배너("곧 휴식") 구간엔 보류할 종류인가. 급한 것(우선순위 1~3)만 예고 중에도 표시.
    var waitsDuringWarning: Bool { priority >= 4 }

    /// 작업 중에만 의미 있는 알림인가 — 대기 중 작업 단계를 벗어나면 폐기.
    var requiresWorkingPhase: Bool {
        switch self {
        case .stretch, .timeNotice: return true
        default:                    return false
        }
    }
}
