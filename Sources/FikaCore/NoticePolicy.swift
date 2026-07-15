import Foundation

/// 토스트 알림 겹침 정책 — 순수 로직(FikaTests로 검증).
/// "떠 있는 것보다 급하면 교체, 아니면 대기 1건" + 예고 배너 중엔 안 급한 알림 보류.
public enum NoticeDecision: Equatable {
    case show      // 즉시 표시 (슬롯 비어 있음)
    case replace   // 떠 있는 토스트를 내리고 표시 (더 급함)
    case wait      // 대기 슬롯으로 (덜 급하거나 예고 배너 중)
}

public enum NoticePolicy {
    /// 새 알림의 판정. priority는 숫자가 작을수록 급함(1이 최고).
    /// - warningHold: 예고 배너가 떠 있고, 이 알림이 예고 중엔 보류해야 하는 종류인가
    /// - currentPriority: 지금 떠 있는 토스트의 우선순위 (없으면 nil)
    public static func decide(newPriority: Int,
                              warningHold: Bool,
                              currentPriority: Int?) -> NoticeDecision {
        if warningHold { return .wait }
        guard let current = currentPriority else { return .show }
        return newPriority < current ? .replace : .wait
    }

    /// 대기 슬롯 갱신: 새 알림이 기존 대기건보다 급하면(같으면 최신이 이김) 교체한다.
    public static func shouldReplacePending(newPriority: Int, pendingPriority: Int?) -> Bool {
        guard let pending = pendingPriority else { return true }
        return newPriority <= pending
    }
}
