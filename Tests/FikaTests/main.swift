import Foundation
import FikaCore

// XCTest 없이(Command Line Tools 환경) 도는 초경량 테스트 러너. 실패가 있으면 종료코드 1.
var failures = 0
func eq<T: Equatable>(_ got: T, _ want: T, _ msg: String) {
    if got == want { print("  ✓ \(msg)") }
    else { failures += 1; print("  ✗ \(msg) — got \(got), want \(want)") }
}

print("ScheduleMath.timeNoticeBucket")
eq(ScheduleMath.timeNoticeBucket(remaining: 3000, period: 300), 9, "50분/5분 → 9단계(첫 알림 45분)")
eq(ScheduleMath.timeNoticeBucket(remaining: 1500, period: 300), 4, "정확히 배수(25분) → 20분부터")
eq(ScheduleMath.timeNoticeBucket(remaining: 1380, period: 300), 4, "비배수(23분) → 20분에 정렬")
eq(ScheduleMath.timeNoticeBucket(remaining: 200, period: 300), 0, "한 주기 미만 → 없음")
eq(ScheduleMath.timeNoticeBucket(remaining: 1000, period: 0), 0, "period 0 방어")

print("\nScheduleMath.isWithinRest (낮 11:30~13:00 = 690~780)")
eq(ScheduleMath.isWithinRest(nowMinutes: 689, start: 690, end: 780), false, "시작 1분 전")
eq(ScheduleMath.isWithinRest(nowMinutes: 690, start: 690, end: 780), true, "시작 시각(포함)")
eq(ScheduleMath.isWithinRest(nowMinutes: 779, start: 690, end: 780), true, "끝 1분 전")
eq(ScheduleMath.isWithinRest(nowMinutes: 780, start: 690, end: 780), false, "끝 시각(배타적)")

print("\nScheduleMath.isWithinRest (자정 넘김 23:00~01:00 = 1380~60)")
eq(ScheduleMath.isWithinRest(nowMinutes: 1380, start: 1380, end: 60), true, "시작")
eq(ScheduleMath.isWithinRest(nowMinutes: 30, start: 1380, end: 60), true, "자정 이후")
eq(ScheduleMath.isWithinRest(nowMinutes: 60, start: 1380, end: 60), false, "끝(배타적)")
eq(ScheduleMath.isWithinRest(nowMinutes: 700, start: 1380, end: 60), false, "윈도우 밖 한낮")
eq(ScheduleMath.isWithinRest(nowMinutes: 700, start: 700, end: 700), false, "start==end → 항상 false")

print("\nScheduleMath.dueShutdownStages (18:00 = 1080 마감)")
eq(ScheduleMath.dueShutdownStages(nowMinutes: 1050, shutdownTime: 1080, fired: []), [30], "30분 전")
eq(ScheduleMath.dueShutdownStages(nowMinutes: 1065, shutdownTime: 1080, fired: []), [15], "15분 전")
eq(ScheduleMath.dueShutdownStages(nowMinutes: 1080, shutdownTime: 1080, fired: []), [0], "도래")
eq(ScheduleMath.dueShutdownStages(nowMinutes: 1051, shutdownTime: 1080, fired: []), [30], "2분 grace 안")
eq(ScheduleMath.dueShutdownStages(nowMinutes: 1052, shutdownTime: 1080, fired: []), [], "grace 지나면 없음")
eq(ScheduleMath.dueShutdownStages(nowMinutes: 1050, shutdownTime: 1080, fired: [30]), [], "이미 쏜 단계 제외")

print("")
if failures == 0 {
    print("✅ 모든 테스트 통과")
} else {
    print("❌ \(failures)개 실패")
    exit(1)
}
