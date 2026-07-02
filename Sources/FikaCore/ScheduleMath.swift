import Foundation

/// 시간 계산 순수 로직 — 상태·UserDefaults·MainActor 의존이 없어 단위 테스트하기 쉽다.
/// 그동안 버그가 나온 지점이 전부 여기 모여 있다(버킷 정렬, 마무리 단계, 고정 휴식 윈도우).
/// 앱 코드(`Sources/fika`)는 이 타입을 호출만 하고, 검증은 `Tests/FikaCoreTests`가 한다.
public enum ScheduleMath {

    /// "남은 시간 알림" 목표 단계: 남은 초를 주기(초)로 끊은 가장 큰 단계.
    /// 정확히 배수면 한 칸 내려 즉시 발화를 막는다. 0이면 더 이상 알림 없음. period<=0이면 0.
    public static func timeNoticeBucket(remaining: Double, period: Double) -> Int {
        guard period > 0 else { return 0 }
        var k = Int((remaining / period).rounded(.down))
        if Double(k) * period >= remaining { k -= 1 }
        return max(0, k)
    }

    /// 지금이 고정 휴식 윈도우 안인지(자정 넘김 포함). start==end면 항상 false.
    /// 인자는 자정 기준 분(0~1439). 끝(end)은 배타적.
    public static func isWithinRest(nowMinutes m: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        if start < end { return m >= start && m < end }
        return m >= start || m < end   // 자정 넘김
    }

    /// 하루 마무리 알림에서 지금 쏴야 할 단계들(30/15/0분 전).
    /// 이미 쏜 단계 제외, 2분 grace(늦게 켜도 지난 단계는 안 쏨). 인자는 자정 기준 분.
    public static func dueShutdownStages(nowMinutes m: Int, shutdownTime: Int, fired: Set<Int>) -> [Int] {
        [30, 15, 0].filter { offset in
            let target = shutdownTime - offset
            return target >= 0 && !fired.contains(offset) && m >= target && m < target + 2
        }
    }
}
