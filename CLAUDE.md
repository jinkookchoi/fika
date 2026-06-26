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
| `Panel.swift` | 메뉴바 팝오버 통합 UI(탭바·상태/시간/알림/설정 탭·진행 링·버튼 스타일) |
| `Idle.swift` | IOKit `IOHIDSystem`/`HIDIdleTime`으로 유휴 시간 측정(모든 HID 입력) |
| `OverlayController/Views/Windows.swift` | 휴식 오버레이·예고 배너 윈도우 |
| `LoginItem.swift` | `SMAppService`로 로그인 자동 실행 |
| `Sound.swift` | 전환 사운드 |

## 중요한 결정 / 함정 (다시 헤매지 말 것)

- **메뉴바는 `MenuBarExtra`가 아니라 `NSStatusItem`으로 만든다.** SwiftUI `MenuBarExtra`가 환경에 따라 안 뜨는 문제가 있어 교체했다.
- **노치 맥에서 아이콘이 안 보이는 건 버그가 아니다.** 메뉴바 오른쪽이 꽉 차면 새 상태아이템이 노치 왼쪽으로 밀려 가려진다. 대응: 컴팩트(아이콘만) 모드(`showMenuBarTime=false`), [Ice](https://icemenubar.app/) 같은 메뉴바 관리 앱, 또는 공간 확보. 코드로는 못 고친다.
- **설정 모델 이름은 `AppSettings`** — SwiftUI의 `Settings` 씬과 충돌해서 그렇게 지었다. 되돌리지 말 것.
- **ad-hoc 서명**(`codesign --sign -`)이라 배포 시 Gatekeeper 경고가 난다. 친구에게 줄 땐 소스 빌드 권장(README "친구에게 공유" 참고). 경고 제거는 Developer ID 공증 필요.
- **유휴 감지**는 입력 "내용"이 아니라 마지막 입력 후 경과 시간만 읽어 권한이 필요 없다.
- 앱은 `.accessory`(Dock 미표시). `Info.plist`에 `LSUIElement=true`.

## 컨벤션

- 주석·UI 텍스트는 한국어.
- 설정 변경은 저장 버튼 없이 즉시 적용(작업/휴식 "분"은 다음 단계부터 반영).
- git 신원은 이 레포 로컬로 개인 계정(`Jinkook Choi <jinkookchoi@gmail.com>`) 설정됨(전역은 회사 계정).
