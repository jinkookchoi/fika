# Fika 종합 진단 보고서 (2026-07-02, v1.6 기준)

전체 소스(약 2,600줄)를 정독하고 실제 운영 로그(`~/Library/Logs/Fika/Fika.log`)를 대조해
"알림이 잘 오지 않는다" 등의 잔 오류 원인을 추적한 결과와, 구조 개선·기능 제안을 정리한다.

---

## 1. 요약 (TL;DR)

- **알림이 안 오는 것처럼 느껴지는 원인은 한 가지가 아니라 여러 개가 겹쳐 있다.**
  가장 유력한 것은 ① 토스트가 항상 **주 모니터에만** 뜸, ② **연기(snooze) 후 알림 스케줄이 재정렬되지 않음**,
  ③ "오늘은 그만" 후 **다음날 자동 재개가 없어** 하루 종일 침묵, ④ **일시정지·고정 휴식 중엔 하루 마무리 알림이
  영영 스킵**되는 것. 이 넷은 코드로 확정한 결함이다.
- **구조적 위험 1건**: sleep 진입 시 타이머를 `invalidate`하고 wake 알림에서만 재시작하는데,
  wake 알림을 한 번이라도 놓치면 **앱 전체가 조용히 죽는다**(메뉴바만 멈춘 채 알림 전무).
  실로그에서 wake 후 32ms 만에 재-sleep하는 dark-wake 패턴이 관측돼, 이 경로가 흔들릴 여지가 실제로 있다.
- **통계 오염 2건**: "지금 휴식하기"가 0분짜리 세션을 기록하고, 연기하면 실제 집중 시간이 크게 과소 기록된다.
- 권장 방향: **타이머를 죽이지 않는 wall-clock 단일화**, **알림 스케줄러 분리**, **알림 이력 뷰**(자가진단),
  **순수 로직 추출 + 테스트**. 상세는 §5·§6.

---

## 2. 진단 범위와 방법

| 항목 | 내용 |
|---|---|
| 코드 | `Sources/fika/` 전 파일 정독 (BreakEngine, OverlayController, Settings, Panel, Stats 등 15개) |
| 로그 | `~/Library/Logs/Fika/Fika.log` 최근 3일치 (sleep/wake·예약 휴식·마무리 알림 이벤트) |
| 리소스 | `Resources/coffee/*`, `Resources/cuts/*`, 번들 조립(`build.sh`) 결과 확인 |
| 관점 | ① 알림 신뢰성(사용자 불만 직결) ② 상태머신/데이터 정합성 ③ 죽은 코드·에너지 ④ 구조/테스트 가능성 |

---

## 3. 결함 목록

심각도 × "알림이 안 온다" 체감 연관도 순. 파일:줄은 2026-07-02 HEAD(`4dd7c97`) 기준.

### A. 알림 신뢰성 (사용자 불만 직결)

#### A-1. [높음] sleep 시 타이머 invalidate → wake 알림을 놓치면 앱 전체 침묵
- 위치: `BreakEngine.swift:420-425` (`handleWillSleep`), `434` (`handleDidWake`의 `defer { startTimer() }`)
- 내용: `willSleepNotification`에서 `timer`를 nil로 만들고, `didWakeNotification`에서만 되살린다.
  두 알림이 항상 짝을 이룬다는 보장은 없다 — dark wake(Power Nap), 빠른 sleep/wake 반복,
  알림 큐 유실 시 **타이머가 영영 재시작되지 않는다**. 그러면 tick이 멈춰 모든 알림·전환·메뉴바 시간이 정지한다.
- 증거: 실로그에 `07-02 07:00:54.442 wake → .474 sleep`(32ms 간격) 같은 초단기 wake/sleep 쌍이 반복 관측됨.
  이런 경계 상황이 잦다는 뜻이고, 한 번만 어긋나면 "앱은 떠 있는데 아무 알림도 안 옴" 상태가 된다.
- 제안: **타이머를 죽이지 말 것.** sleep 중엔 어차피 안 울리고, 대신 tick에서 "직전 틱과의 시간 차"를 재서
  큰 gap(예: 10초 이상)이면 지금의 `handleDidWake` 보정을 수행한다. sleepAt/didWake 의존이 사라져
  코드도 단순해진다. (§5-1 참고)

#### A-2. [높음] 모든 토스트·예고 배너가 `NSScreen.main`(주 모니터)에만 표시
- 위치: `OverlayController.swift:80, 99, 127, 146, 165, 182` — 전부 `NSScreen.main` 고정
- 내용: `NSScreen.main`은 키 윈도우가 있는 화면인데, 메뉴바 전용(accessory) 앱은 키 윈도우가 없어
  사실상 **항상 주(내장) 디스플레이**로 떨어진다. 외장 모니터에서 작업 중이면 동작 알림·남은 시간 알림·
  예고 배너·마무리 알림이 전부 다른 화면에 떠서 못 본다. **"알림이 안 온다"의 가장 유력한 후보.**
- 제안: 마우스 커서가 있는 화면(`NSEvent.mouseLocation`이 포함된 `NSScreen`)에 띄우거나,
  설정으로 "모든 화면에 표시" 옵션 제공. 휴식 오버레이(fullscreen)는 이미 전 화면 대응이므로 토스트만 고치면 된다.

#### A-3. [중간] 연기(snooze) 후 알림 스케줄이 재정렬되지 않음
- 위치: `BreakEngine.swift:579-592` (`snooze()`)
- 내용: `snooze()`는 `setRemaining()`만 부르고 `resetTimeNoticeBucket()`·`nextMicroBreak` 재설정을 안 한다.
  - `timeNoticeFinalFired`가 true인 채 남아 연장 구간에서 "곧 휴식" 마지막 알림이 다시 안 온다.
  - `timeNoticeBucket`이 이미 소진(0)됐으면 연장 구간 내내 남은 시간 알림이 없다.
  - 휴식 중 연기(`.breaking` → `.working`)는 사실상 새 미니 작업 세션인데 마이크로 브레이크 기준점도 옛날 것.
- 제안: `snooze()`에서 `resetTimeNoticeBucket(forRemaining:)` 호출(이 함수가 `timeNoticeFinalFired`도 리셋함).
  `.breaking`에서 연기할 땐 `nextMicroBreak`도 재설정.

#### A-4. [중간] "오늘은 그만" 후 다음날 자동 재개 없음
- 위치: `BreakEngine.swift:268-270` (`quietForToday()` → `togglePause()`)
- 내용: 마무리 알림의 "오늘은 그만"은 그냥 일시정지다. 다음날 아침 재개 버튼을 안 누르면
  **하루 종일 알림이 하나도 없다.** 사용자 입장에선 "요즘 알림이 잘 안 온다"로 체감되기 딱 좋다.
  게다가 일시정지 중엔 메뉴바가 정지 프레임이라 눈치채기도 어렵다.
- 제안: `quietForToday()`가 "오늘까지만 조용" 플래그(날짜키)를 남기고, tick에서 날짜가 바뀌었으면
  자동 재개(또는 첫 입력 감지 시 재개 + "좋은 아침" 토스트). 일반 일시정지와 구분되는 상태로.

#### A-5. [중간] 일시정지·고정 휴식 중엔 하루 마무리 알림이 영영 스킵
- 위치: `BreakEngine.swift:176-177` (tick 첫머리 `guard phase != .paused`, `handleScheduledRest() return`)
- 내용: `handleShutdown()`은 tick 안에서만 도는데, 일시정지면 tick 자체가 return하고
  고정 휴식 중이면 `handleScheduledRest()`가 true를 돌려 그 아래 로직을 전부 건너뛴다.
  마무리 알림은 2분 grace라, 그 사이 단계(30/15/0분 전)가 지나가면 **그날은 다시 안 온다.**
  마무리 시각이 점심(고정 휴식)과 겹치는 경우는 드물지만, "일시정지 중이라 마무리 알림을 못 받음"은 흔한 시나리오.
- 제안: `handleShutdown()`(그리고 필요하면 `handleScheduledRestPrealert()`)은 phase와 무관하게 돌린다 —
  tick 최상단에서 paused여도 이 둘만은 호출. 시각 기반 알림은 상태머신과 독립인 게 자연스럽다.

#### A-6. [낮음] 재개·짧은 wake 직후 뜬금없는 동작 토스트
- 위치: `BreakEngine.swift:323-332` (`handleMicroBreak`), `529-540` (`togglePause`), `451-455` (짧은 sleep 보정)
- 내용: `nextMicroBreak`는 wall-clock 절대 시각이라, 일시정지 해제·짧은 sleep 복귀 직후엔 이미 과거가 되어
  **복귀하자마자 동작 알림이 즉시 발화**한다. 사용자에겐 "왜 지금?"으로 느껴진다.
- 제안: `togglePause()` 재개 시와 `handleDidWake`의 "남은 시간 보존" 분기에서
  `nextMicroBreak`도 같은 폭만큼 밀어준다.

#### A-7. [낮음] 남은 시간 알림 주기를 세션 중 바꾸면 어긋남
- 위치: `Settings.swift:84` (`timeNoticeMinutes`), `BreakEngine.swift:365-372` (`resetTimeNoticeBucket`)
- 내용: 버킷은 작업 시작 때 당시 주기로 계산된다. 세션 중 주기를 줄이면(30→5분) 버킷 수가 모자라
  남은 세션 동안 알림이 거의 안 오고, 늘리면(5→30분) 다음 틱에 한 번 즉시 발화한다.
- 제안: `timeNoticeMinutes`/`timeNoticeEnabled` didSet에서 엔진에 재정렬을 알리는 훅(§5-3).

#### A-8. [낮음] App Nap / 타이머 관용치 미지정
- 위치: `BreakEngine.swift:71-76`, `FikaApp.swift:49-51`
- 내용: LSUIElement 앱은 App Nap 대상이 될 수 있고, 그러면 타이머가 지연·병합된다.
  현재 0.1초 UI 타이머가 사실상 App Nap을 막아주고 있지만 그건 우연에 기댄 것이다(§C-3에서 이 타이머 최적화를
  제안하는데, 그러면 이 우연도 사라진다).
- 제안: `ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "break timer")`로
  명시적으로 App Nap을 막는다. 1초 엔진 타이머엔 `tolerance = 0.2` 정도를 줘 에너지도 아낀다.

### B. 상태머신 / 데이터 정합성

#### B-1. [중간] `breakNow()`가 0분짜리 가짜 세션을 기록하고 긴 휴식 주기를 왜곡
- 위치: `BreakEngine.swift:564-568` (`breakNow`), `490-501` (`enterBreak`)
- 내용: `breakNow()`는 `setRemaining(0)`으로 **`phaseDuration`을 1초로 덮어쓴 뒤** `enterBreak()`를 부른다.
  `enterBreak()`는 `phaseDuration/60`(≈0.017분)을 세션으로 기록하고 `completedWork`도 +1 한다.
  결과: ① "오늘 N회"가 수동 휴식마다 부풀고 ② 긴 휴식 주기(4번째마다)가 당겨지며
  ③ 실제로 일한 시간(예: 50분 중 30분)은 통째로 유실된다.
- 제안: 실제 작업 경과를 별도로 추적해 그걸 기록(§B-2와 같은 해법), 최소한 `breakNow()`에선
  `setRemaining(0)` 전의 경과분을 기록하거나 아예 기록·카운트를 생략.

#### B-2. [중간] 세션 기록이 "실제 집중 시간"이 아니라 "계획된 길이"
- 위치: `BreakEngine.swift:491` (`SessionStore.record(minutes: phaseDuration / 60, ...)`)
- 내용: `phaseDuration`은 마지막 `setRemaining()`이 정한 값이다.
  - 예고 배너에서 연기: 남은 60초 + 5분 = `phaseDuration` 6분 → **50분 일하고 6분으로 기록.**
  - "이번만 — 휴식까지 5분": 이미 40분 일했어도 5분으로 기록.
  - 휴식 중 연기로 생긴 5분 미니 세션은 별도 1회로 또 기록(회수 부풀림).
- 제안: 엔진에 `workedSeconds` 누적 필드를 두고(작업 중 tick마다 +1, away/pause 제외),
  `enterBreak()`에서 그 값을 기록 후 리셋. 통계가 비로소 "실제 집중 시간"이 된다.

#### B-3. [낮음] 고정 휴식 중 sleep→wake 시 working으로 튕겼다가 재진입 + 토스트 중복
- 위치: `BreakEngine.swift:434-457` (`handleDidWake`) — `.scheduledRest` 분기 부재
- 내용: 점심 휴식 중 노트북을 덮었다 열면(휴식 시간 이상 수면) `startWork()`가 불려 잠깐 `.working`이 됐다가
  다음 tick에 `enterScheduledRest()`로 재진입하며 **"점심 휴식, 13:00까지 쉬어요" 토스트가 또 뜬다.**
- 제안: `handleDidWake` 첫머리에 `if phase == .scheduledRest { refreshPresentation(); return }` —
  어차피 절대 시각 기반이라 tick의 `handleScheduledRest()`가 알아서 처리한다.

#### B-4. [낮음] 자리 비움 복귀 시 무조건 작업 리셋 — 임계값과 휴식 시간의 불일치
- 위치: `BreakEngine.swift:387-403` (`handleIdle`), 기본값 `idleThresholdMinutes=5`, `breakMinutes=10`
- 내용: 5분만 자리를 비워도 "쉬고 왔다"로 간주해 작업을 처음부터 리셋한다.
  반면 sleep 복귀는 `slept >= breakMinutes`(10분)일 때만 리셋한다 — **같은 "자리 비움"인데 기준이 다르다.**
  잠깐 회의 다녀왔더니 45분 진행하던 세션이 0부터 시작 → "타이머가 제멋대로"로 체감될 수 있다.
- 제안: 유휴 복귀도 sleep과 같은 규칙으로 — 비운 시간이 `breakMinutes` 이상이면 리셋,
  미만이면 동결 해제만(이미 동결돼 있으니 그대로 이어감). 규칙이 하나로 통일된다.

### C. 죽은 코드 / 에너지 / 사소

#### C-1. `CoffeeIcon` 폴백이 실제로는 연결돼 있지 않음
- 위치: `FikaApp.swift:59-68`, `CoffeeAnimation.swift:22` (`hasFrames` — 아무도 안 씀), `CoffeeIcon.swift` 전체
- 내용: CLAUDE.md엔 "영상 프레임 없을 때 CoffeeIcon 폴백"이라고 돼 있지만, `updateButton()`은
  프레임이 없으면 `button.image = nil`을 넣을 뿐이다. 시간 표시까지 꺼져 있으면 **메뉴바 아이콘이 투명**해진다.
  `steamPhase`(FikaApp.swift:12,56)도 증가만 하고 아무 데도 안 쓰는 죽은 코드.
- 제안: coffee 테마에서 `CoffeeAnimation.hasFrames == false`면 `CoffeeIcon`(또는 emoji)로 폴백하고,
  `steamPhase`는 삭제. 아니면 CoffeeIcon.swift를 아예 지우고 CLAUDE.md 문구를 고친다.

#### C-2. 로그 회전이 앱 시작 시 1회뿐
- 위치: `Log.swift:47-53`, 호출은 `FikaApp.swift:15`
- 내용: 메뉴바 앱은 몇 주씩 안 꺼진다. 디버그 모드로 오래 두면 512KB 상한을 무한히 초과.
- 제안: `write()`에서 N번째 기록마다, 또는 하루 1회 `rotateIfNeeded()` 호출.

#### C-3. 10Hz 메뉴바 타이머 상시 구동
- 위치: `FikaApp.swift:49-51`
- 내용: emoji/symbol 테마이거나 커피가 정지 프레임(일시정지·자리비움)일 때도 0.1초마다 이미지·타이틀을 다시 쓴다.
  개인용 앱이라 치명적이진 않지만 상시 wakeup은 배터리에 좋지 않다.
- 제안: coffee 테마 + 재생 중일 때만 10Hz, 그 외엔 1Hz로 낮춤(시간 표시는 1초 단위면 충분).
  단, A-8의 `beginActivity`를 먼저 넣어야 App Nap 부작용이 없다.

#### C-4. 기타 한 줄짜리
- `resetToDefaults()`가 `microBreak*`·`timeNotice*`·`stretchTips`·`debugMode`를 안 되돌림 (`Settings.swift:135-156`) — 의도라면 주석으로 명시.
- `isWarning`이 `isAway`를 안 봐서 자리 비움 중에도 예고 배너가 떠 있음 (`BreakEngine.swift:81-83`) — 무해하지만 어색.
- `warningSeconds`를 크게(≥ 알림 주기) 잡으면 `!isWarning` 가드 때문에 마지막 남은 시간 알림이 통째로 빠짐 — 예고 배너가 대신 떠 있으니 수용 가능, 인지만.
- 크래시 핸들러의 `Log.write` 직접 호출은 로그 큐와 경합 가능 (`Log.swift:58-63`) — 크래시 맥락이라 실익 대비 무시 가능.

---

## 4. "알림이 안 온다" 시나리오별 원인 매핑

| 체감 증상 | 가장 유력한 원인 |
|---|---|
| 외장 모니터로 일할 때 유독 못 봄 | A-2 (주 모니터 고정) |
| 어느 날부터 하루 종일 조용함 | A-4 (오늘은 그만 → 재개 안 함) 또는 A-1 (타이머 사망) |
| 연기했더니 그 뒤로 남은 시간 알림이 없음 | A-3 |
| 마무리 알림이 안 온 날이 있음 | A-5 (일시정지 중) 또는 A-1 |
| 복귀하자마자 뜬금없는 동작 알림 | A-6 |
| 알림 주기 바꿨더니 이상해짐 | A-7 |
| "오늘 N회"가 실제보다 많음/집중 시간이 적음 | B-1, B-2 |

---

## 5. 구조 개선 제안

### 5-1. Wall-clock 단일화 — sleep/wake 특수 처리 제거
현재 시간 흐름 제어가 세 갈래다: ① 1초 Timer tick ② willSleep/didWake 보정 ③ HIDIdleTime 유휴 감지.
①과 ②를 합칠 수 있다 — **타이머는 절대 죽이지 않고**, tick에서 `lastTick`과의 gap을 재서
gap이 크면(≈sleep이었으면) 지금의 wake 보정 로직을 그대로 태운다.

```swift
private var lastTick = Date()
private func tick() {
    let gap = Date().timeIntervalSince(lastTick)
    lastTick = Date()
    if gap > 10 { handleLongGap(gap) }   // 기존 handleDidWake 본문
    ...
}
```
효과: A-1(침묵 리스크) 원천 제거, `sleepAt`/`observeSleepWake` 삭제, 코드가 줄고 테스트가 쉬워진다.
(willSleep 로그는 남기고 싶으면 관찰만 유지하고 타이머는 건드리지 않는다.)

### 5-2. `tick()` 분해 — 알림 스케줄러 분리
`tick()`이 상태 전환 + 5종 알림 판정을 전부 안고 있다(마이크로 브레이크, 남은 시간, 마지막 알림, 마무리, 사전 예고).
`AlertScheduler` 같은 타입으로 "언제 무엇을 쏠지" 판정만 떼어내면:
- A-5(일시정지 중 시각 기반 알림 스킵)가 구조적으로 해결된다 — 스케줄러는 phase와 독립으로 돈다.
- 발화 조건이 순수 함수가 되어 테스트 가능해진다(§5-4).
- 새 알림 종류를 추가할 때 tick을 안 건드린다.

### 5-3. 설정 변경 → 엔진 재정렬 훅
지금은 설정 didSet이 UserDefaults 저장만 한다. 주기류(`timeNoticeMinutes`, `microBreakMinutes`,
`scheduledRest*`)가 바뀌면 엔진의 버킷/예정 시각이 낡는다(A-7).
`AppSettings`에 `onScheduleChange: (() -> Void)?` 콜백 하나를 두고 엔진이 구독해
`resetTimeNoticeBucket()`·`nextMicroBreak` 재계산을 하면 깔끔하다. (Combine 없이 클로저면 충분)

### 5-4. 순수 로직 추출 + 테스트
지금 테스트가 0개인데, 버그가 나온 지점이 전부 "시간 계산 순수 로직"이다 — 버킷 정렬, 마무리 단계 판정,
고정 휴식 윈도우(자정 넘김 포함), gap 보정 규칙. 이런 것들을 `Date`를 주입받는 순수 함수/작은 struct로 빼면
`swift test`로 검증 가능하다(Xcode 불필요, `Package.swift`에 testTarget만 추가).
최소 세트: 자정 넘김 윈도우, 버킷 재정렬(경계 즉시발화 방지), 마무리 30/15/0 + grace, gap 보정 분기.

### 5-5. 알림 이력 = 최고의 자가진단 도구
"알림이 안 왔다"를 확인할 방법이 지금은 디버그 로그뿐이다.
모든 토스트 발화를 메모리 링버퍼(최근 20건: 시각·종류·문구)에 남기고 패널(알림 탭 하단)에서 보여주면
"안 온 건지, 놓친 건지"를 사용자가 즉시 판별할 수 있다. 구현 비용 대비 효과가 가장 크다.

---

## 6. 기능 제안

우선순위 순:

1. **알림 테스트 버튼** (알림 탭): 동작/남은 시간/마무리 토스트를 즉석에서 띄워본다.
   멀티 모니터에서 "어느 화면에 뜨는지"도 바로 확인 가능 — A-2와 세트.
2. **알림 이력 보기** (§5-5).
3. **토스트 표시 화면 선택**: 마우스 있는 화면(기본 추천) / 주 화면 / 모든 화면.
4. **다음날 자동 재개** (A-4 해법): "오늘은 그만"이 날짜가 바뀌면 스스로 풀린다.
5. **화면 공유·발표 감지**: `CGDisplayStream`/`SCShareableContent` 없이도
   `CGSessionCopyCurrentDictionary`나 미러링 여부(`NSScreen` 프레임 중복)로 근사 감지해,
   공유 중엔 전체화면 덮기를 soft로 자동 강등. 회의 중 화면이 덮이는 최악의 UX 방지.
6. **통계 개선**: B-2 해결로 "실제 집중 시간"이 쌓이면 → 시간대별 히트맵(어느 시간에 집중했나),
   계획 대비 실제(연기·건너뛰기 비율) 표시가 의미를 갖는다.
7. **긴 휴식 카운터 표시**: `completedWork`가 지금 몇이고 몇 번째에 긴 휴식인지 상태 탭에 점(●●○○)으로.
   앱 재시작 시 리셋되는 것도 UserDefaults에 날짜키와 함께 보존하면 좋다.

---

## 7. 권장 작업 순서

| 단계 | 항목 | 근거 |
|---|---|---|
| 1 | A-1 타이머 불사(不死)화 (§5-1) | 침묵 리스크 제거 + 코드 단순화, 다른 수정의 토대 |
| 2 | A-2 토스트 화면 수정 + 기능 1(알림 테스트) | "알림 안 옴" 체감 원인 1순위, 즉시 검증 가능 |
| 3 | A-3 snooze 재정렬, A-6 스테일 마이크로브레이크, B-3 scheduledRest wake | 각 5줄 내외의 국소 수정 |
| 4 | A-4 다음날 자동 재개, A-5 시각 기반 알림 독립화 | 침묵 시나리오 마무리 |
| 5 | B-1·B-2 실제 집중 시간 추적 | 통계 신뢰 회복 (이후 기능 6의 전제) |
| 6 | §5-4 테스트 도입, C-1~C-3 정리 | 재발 방지·청소 |

각 단계는 독립적으로 배포 가능하며, 1~3단계만으로도 "알림이 잘 안 온다"는 체감 문제의 대부분이 해소될 것으로 본다.
