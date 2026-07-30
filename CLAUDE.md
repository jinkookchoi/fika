# CLAUDE.md

이 파일은 Claude Code(및 에이전트)가 이 저장소에서 작업할 때 참고하는 가이드다.
사용자 응답은 **한국어**로 한다.

## 프로젝트

**Fika** — 오래 앉지 않도록 작업/휴식 사이클을 알려주는 macOS 메뉴바 앱.
개인용. Swift + SwiftUI, **Xcode 없이 Command Line Tools 만으로** 빌드.
번들 ID `com.jinkookchoi.fika`. 사용자 대상 설명은 `README.md` 참고.

> 폴더명은 아직 `huesic`(앱은 Fika로 개명 완료). 폴더 rename은 세션 cwd 깨짐 방지로 보류 중.

## 빌드 & 실행

```bash
./build.sh              # swift build (release) → Fika.app 조립 + ad-hoc 서명
swift build -c debug    # 컴파일만 빠르게 검증할 때
swift run FikaTests     # 순수 로직 단위 테스트 (FikaCore, XCTest 미사용 — CLT 환경)
./package.sh            # 빌드 + 친구 공유용 Fika-<버전>.zip 생성
open Fika.app           # 실행 (메뉴바 전용, Dock 아이콘 없음)
pkill -f MacOS/Fika     # 종료
```

- `Fika.app/Contents/MacOS/Fika` 를 직접 실행하면 콘솔 로그(`NSLog`)를 볼 수 있다.
- Xcode 프로젝트 없음. SwiftPM(`Package.swift`) + `build.sh`로 `.app` 번들을 수동 조립한다.
- Swift 언어 모드는 `.v5` 고정(엄격 동시성 회피). UI 코드는 `@MainActor`.

## 구조 (Sources/fika/)

| 파일 | 역할 |
|---|---|
| `FikaApp.swift` | 진입점 + `AppDelegate`. **`NSStatusItem`+`NSPopover`로 메뉴바 직접 생성** |
| `BreakEngine.swift` | 작업/휴식 상태머신(두뇌). `@MainActor` 싱글톤 `.shared` |
| `Settings.swift` | 설정 모델 **`AppSettings`** (UserDefaults 자동 저장) + enum들 |
| `Panel.swift` | 메뉴바 팝오버 통합 UI(탭바·상태/시간/알림/동작/분석/설정 6탭·진행 링·차트·버튼 스타일) |
| `Idle.swift` | IOKit `IOHIDSystem`/`HIDIdleTime`으로 유휴 시간 측정(모든 HID 입력) |
| `OverlayController/Views/Windows.swift` | 휴식 오버레이·예고 배너·시작/동작/남은시간 토스트·메뉴바 호버 팁 윈도우 |
| `CoffeeAnimation.swift` | **메뉴바 커피 마스코트** — Veo 영상에서 뽑은 프레임 시퀀스 재생(상태별 work/warning/done). `Resources/coffee/<상태>/frame_NNN.png` |
| `MascotCut.swift` | 화면 UI(휴식·예고·복귀·토스트·진행 링)용 마스코트 정지 컷. `Resources/cuts/<상태>.png` |
| `CoffeeIcon.swift` | 절차적 커피잔(코드 드로잉). 지금은 메뉴바 폴백용(영상 프레임 없을 때만) |
| `Log.swift` | 파일 로거(`~/Library/Logs/Fika/`) + 미처리 예외 핸들러 |
| `Stats.swift` | **집중 분석** — 완료 세션 기록 저장(`~/Library/Application Support/Fika/sessions.json`) + 일/주/월 집계. `SessionStore.shared` |
| `LoginItem.swift` | `SMAppService`로 로그인 자동 실행 |
| `Sound.swift` | 전환 사운드 |

## 중요한 결정 / 함정 (다시 헤매지 말 것)

- **메뉴바는 `MenuBarExtra`가 아니라 `NSStatusItem`으로 만든다.** SwiftUI `MenuBarExtra`가 환경에 따라 안 뜨는 문제가 있어 교체했다.
- **노치 맥에서 아이콘이 안 보이는 건 버그가 아니다.** 메뉴바 오른쪽이 꽉 차면 새 상태아이템이 노치 왼쪽으로 밀려 가려진다. 대응: 컴팩트(아이콘만) 모드(`showMenuBarTime=false`), [Ice](https://icemenubar.app/) 같은 메뉴바 관리 앱, 또는 공간 확보. 코드로는 못 고친다.
- **설정 모델 이름은 `AppSettings`** — SwiftUI의 `Settings` 씬과 충돌해서 그렇게 지었다. 되돌리지 말 것.
- **ad-hoc 서명**(`codesign --sign -`)이라 배포 시 Gatekeeper 경고가 난다. 친구에게 줄 땐 소스 빌드 권장(README "친구에게 공유" 참고). 경고 제거는 Developer ID 공증 필요.
- **유휴 감지**는 입력 "내용"이 아니라 마지막 입력 후 경과 시간만 읽어 권한이 필요 없다.
- 앱은 `.accessory`(Dock 미표시). `Info.plist`에 `LSUIElement=true`.
- **macOS 26+ 크래시 함정: SwiftUI를 borderless 창/팝오버에 얹을 땐 `sizingOptions = []` 필수.** `NSHostingView`/`NSHostingController`가 콘텐츠 크기에 맞춰 창 제약을 자동 갱신하는데, macOS 26의 강화된 Auto Layout 검증이 이 갱신을 레이아웃 패스 중 재진입으로 감지하면 `NSException`("…more Update Constraints in Window passes than there are views…")을 던져 앱을 죽인다(`EXC_BREAKPOINT`/`SIGTRAP`, 특히 sleep/wake 후 디스플레이 재계산 시). 우리 오버레이·팝오버는 전부 프레임/`contentSize`를 직접 지정하므로 자동 사이징이 불필요 → `OverlayController.setHosted()`와 팝오버 호스팅에서 `sizingOptions = []` 적용. **새 오버레이 창을 추가하면 반드시 `setHosted(_:_:)`를 거칠 것.** (이건 우리만의 버그가 아니라 macOS 26 회귀 — 같은 OS의 다른 SwiftUI 앱들도 동일 크래시)
- **크래시·이상 동작 추적**: 설정 "문제 해결" → 디버그 로그를 켜면 상태 전환·sleep/wake·오버레이 동작이 `~/Library/Logs/Fika/Fika.log`에 쌓인다. sleep/wake·앱 시작·미처리 예외는 디버그 꺼도 항상 기록.
- **마스코트 리소스 파이프라인**: 메뉴바·화면 마스코트는 **Veo 영상 → 그린스크린 키잉(`chromakey`+`despill`) → `magick -trim` → 프레임/컷**으로 만든다. 컵 색·음료 종류를 바꾸려면 **영상을 새로 생성해야** 한다(코드 hue 변환은 눈·커피색까지 변해 부자연). 색 버전당 번들도 그만큼 커진다.
- **메뉴바(18px)에 통합 위젯은 하지 말 것.** 말풍선·진행바·색 숫자 등을 커피와 한 묶음으로 합치는 시도는 다 실패했다 — **영상 마스코트(완성 일러스트)와 코드로 그린 UI는 그림체가 충돌**하고, 18px에선 디테일이 뭉갠다. 메뉴바는 **마스코트 + 옆 숫자**로 단순하게 두고, 통합·풍부함은 큰 화면(패널 진행 링 등)에서 푼다.

## 컨벤션

- 주석·UI 텍스트는 한국어.
- 설정 변경은 저장 버튼 없이 즉시 적용(작업/휴식 "분"은 다음 단계부터 반영).
- **데이터 저장**: 설정은 UserDefaults, 집중 세션 기록은 `~/Library/Application Support/Fika/sessions.json`(Codable JSON). 둘 다 앱 번들과 별개라 재설치/재빌드해도 유지된다.
- **집중 세션은 "완료분"만 집계** — 작업→휴식 정상 전환(`enterBreak`) 시 1건 기록(`SessionStore.record`). 리셋·딴짓한 미완료 세션은 안 센다.
- **작업 중 동작 알림(마이크로 브레이크)**: `microBreakEnabled`(기본 켬)면 작업 중 `microBreakMinutes`마다 동작 토스트. 곧 휴식 예고 구간엔 안 띄운다. 동작 문구는 `stretchTips`(설정에서 편집). UI는 **동작 탭**(가만히 앉아 있지 말라는 신체 동작 전용).
- **하루 마무리 알림(shutdown)**: `shutdownEnabled`(기본 끔)·`shutdownTime`(자정 기준 분, 기본 18:00). `tick()`의 `handleShutdown()`이 마칠 시각 **30/15/0분 전**에 토스트 1회씩(단계별 `shutdownFiredStages`, 자정에 리셋, 2분 grace라 늦게 켜도 지난 단계는 안 쏨). **강제 종료 안 함.** 도래(0분) 토스트엔 오늘 집중 요약 + "오늘은 그만" 버튼 → `quietForToday()`(기존 일시정지 재사용). UI는 **알림 탭**.
- **일시정지는 하루를 넘기지 않는다**: 수동 일시정지·"오늘은 그만" 공통으로 시작 날짜(`pausedDay`)를 기록하고, 날이 바뀐 뒤 실제 입력이 감지되면 `handlePausedNextDayResume()`이 작업 사이클을 새로 시작(A-4). 해제를 잊고 며칠씩 정지 상태로 두는 사고 방지.
- **고정 휴식 시간대(scheduledRest)**: `scheduledRestEnabled`(기본 끔)·`scheduledRestStart`/`End`(자정 기준 **분**)·`scheduledRestLabel`. 매일 그 시각엔 `Phase.scheduledRest`로 들어가 작업 사이클을 멈추고 남은 시간만 표시(화면 안 덮음). `tick()` 맨 앞 `handleScheduledRest()`가 진입/유지/이탈 처리하고 true면 평소 로직 skip. **절대 시각(wall-clock) 기반이라 sleep/wake 보정 불필요** — 깨어나면 "지금 윈도우 안인가"만 본다. 진입 시 미완료 작업 세션은 기록 안 함(컨벤션), 종료 시 `startWorkFromBreak()`로 작업 새로 시작. **시작 5분 전 사전 예고** 토스트 1회(`handleScheduledRestPrealert`, 하루 1회·자정 리셋). UI는 **시간 탭**(DatePicker는 Int 분 ↔ Date 브리지). `Phase`에 case 추가 시 `phaseColor`/`iconEmoji`/`iconSymbol`/`phaseLabel`/`mascotCut`/`coffeeLevel` 등 switch를 빠짐없이 채울 것(컴파일러가 잡아줌).
- **남은 시간 알림**: `timeNoticeEnabled`(기본 끔)·`timeNoticeMinutes`. **메뉴바 시간 표시(`showMenuBarTime`)와 무관한 별도 토글**(UI는 **알림 탭**). 작업 중 주기마다 "휴식까지 N분" 토스트 + **커피잔 줄**(1잔=5분, 긴 세션은 10/15분 단위로 자동 확대 → 항상 ≤12잔). 겹침 처리는 아래 Notice 파이프라인이 담당.
- **토스트 알림 파이프라인(Notice)**: 잠깐 떴다 사라지는 알림 5종(시작·동작·마무리·고정휴식·남은시간)은 전부 `Notice` enum → `OverlayController.post()` 단일 진입점. **새 알림 추가 = Notice case 추가**(priority/validity/duration switch를 컴파일러가 강제) + `makeSpec()` 채우기 — show 메서드를 새로 만들지 말 것. 겹침 정책은 `NoticePolicy`(FikaCore, FikaTests로 검증): **급하면 교체, 아니면 대기 1건**(validity 만료 시 조용히 폐기), 예고 배너 중엔 우선순위 4 이하 보류. 대기건 표시는 `tick()`의 `overlay.flushPending()`. 뷰는 `ToastView` 한 벌(`ToastSpec` 내용 + `ToastTheme` 강조색, 폭 고정 440/500·높이 가변). **창 실측 함정**: 크기는 표시 전 일회용 probe `NSHostingView.fittingSize`로 재고, 표시용 루트뷰는 반드시 `.frame(maxWidth:.infinity, maxHeight:.infinity)`로 유연하게 얹을 것 — 고정 크기 루트를 얹거나 표시용 호스트에 fittingSize를 물으면 창이 카드 크기로 줄어 글로우·등장 모션이 잘린다. 시각 검증은 `FIKA_TEST_TOAST=<start|stretch|time|time15|timeFinal|shutdown|shutdownStop|rest|collision>` (+`FIKA_SNAPSHOT_OUT=<png>`) 환경변수.
- **예고 배너(WarningView)는 Notice 파이프라인 밖** — 알림이 아니라 상태 표시(휴식 진입까지 상시). post()가 `engine.isWarning`을 정책 입력으로만 참조한다.
- **메뉴바 호버 팁**: 시간을 감췄을 때(`showMenuBarTime=false`) 상태아이템에 마우스를 올리면 상태·남은 시간을 작은 카드(`HoverTipView`)로 표시. OS 툴팁 대신 직접 구현(지연 없음). 트래킹은 `NSTrackingArea(.inVisibleRect)`, 셀렉터는 `@objc(mouseEntered:)`/`@objc(mouseExited:)`로 명시(AppDelegate가 NSResponder가 아니라서).
- git 신원은 이 레포 로컬로 개인 계정(`Jinkook Choi <jinkookchoi@gmail.com>`) 설정됨(전역은 회사 계정).
