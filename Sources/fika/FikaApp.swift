import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let engine = BreakEngine.shared
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var titleTimer: Timer?
    private var titleInterval: TimeInterval = 0
    /// App Nap 방지 활동 토큰 (살아 있는 동안 App Nap이 억제됨)
    private var activityToken: NSObjectProtocol?
    /// 김 애니메이션 위상 (커피 테마용)
    private var steamPhase: Double = 0
    /// 심볼 테마용 SF Symbol 캐시 (이름당 한 번만 생성)
    private var symbolCache: [String: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.rotateIfNeeded()
        Log.installCrashHandler()
        Log.event("앱 시작 — debug=\(engine.settings.debugMode)")

        // Dock 아이콘 없이 메뉴바 전용으로 동작.
        NSApp.setActivationPolicy(.accessory)

        // 메뉴바 상태 아이템 생성 (NSStatusItem — 가장 확실한 방식)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            // 고정폭 숫자 폰트 → 카운트다운 시 폭이 출렁이지 않음.
            let size = button.font?.pointSize ?? NSFont.systemFontSize
            button.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            // 마우스 오버 추적 → 시간 감춤 상태에서 호버 팁을 띄운다.
            // .inVisibleRect: 버튼 폭이 바뀌어도(시간 표시 on/off) 추적 영역이 자동으로 따라간다.
            button.addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }
        updateButton()

        // 팝오버 = 통합 패널
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 540)
        // 콘텐츠는 여기서 만들지 않는다. 열 때 만들고 닫을 때 버린다(popoverDidClose).
        // 계속 붙여두면 패널이 보이지 않아도 SwiftUI 가 engine 을 구독한 채 매 tick 재렌더하고,
        // 그 CoreAnimation 커밋이 상시 CPU와 mach port 증가로 이어진다.
        popover.delegate = self

        // App Nap 방지 — 안 하면 타이머가 지연·병합돼 알림이 늦거나 멈출 수 있다(A-8).
        // 시스템 idle sleep은 허용(우리는 tick gap 보정으로 처리).
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Fika 작업/휴식 타이머")

        // 메뉴바 갱신 — 커피 프레임 재생 중엔 ~10Hz, 그 외(이모지·심볼·정지 프레임)엔 1Hz로 낮춤(C-3).
        scheduleTitleTimer(interval: 0.1)

        // 개발용: FIKA_TEST_TOAST=start|stretch|time|timeFinal|shutdown|shutdownStop|rest 로 실행하면
        // 1초 뒤 해당 토스트를 한 번 띄운다(시각 확인용). 일반 실행엔 영향 없음.
        if let kind = ProcessInfo.processInfo.environment["FIKA_TEST_TOAST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [engine] in
                engine.postTestToast(kind)
            }
            // FIKA_SNAPSHOT_OUT=<경로.png> 를 함께 주면 토스트를 PNG로 저장하고 종료한다.
            if let out = ProcessInfo.processInfo.environment["FIKA_SNAPSHOT_OUT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [engine] in
                    engine.snapshotToast(to: out)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// 메뉴바 갱신 타이머를 주어진 주기로 (재)설정한다. 주기가 그대로면 무시(불필요한 재생성 방지).
    private func scheduleTitleTimer(interval: TimeInterval) {
        guard interval != titleInterval else { return }
        titleTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        titleTimer = t
        titleInterval = interval
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        steamPhase += 0.6
        let showTime = engine.settings.showMenuBarTime
        switch engine.settings.iconTheme {
        case .coffee:
            // 상태별 영상 마스코트 프레임 재생. (일시정지·자리비움이면 정지 프레임)
            let clip: CoffeeAnimation.Clip =
                (engine.phase == .breakHold || engine.phase == .scheduledRest) ? .done
                : (engine.phase == .working && engine.isWarning) ? .warning
                : .work
            let frozen = engine.phase == .paused || engine.isAway || engine.phase == .scheduledRest
            if let frame = frozen ? CoffeeAnimation.still(clip) : CoffeeAnimation.next(clip) {
                setImage(button, frame)
            } else {
                // 영상 프레임이 없으면 절차적 커피잔으로 폴백(안 하면 아이콘이 투명해짐). steamPhase가 여기서 쓰인다.
                setImage(button, CoffeeIcon.image(level: engine.coffeeLevel, steamPhase: steamPhase,
                                                  away: engine.isAway, paused: engine.phase == .paused,
                                                  warning: engine.isWarning ? engine.warningIntensity : 0))
            }
            setPosition(button, showTime ? .imageLeading : .imageOnly)
            setTitle(button, showTime ? " \(engine.menuTimeString)" : "")
        case .emoji:
            setImage(button, nil)
            setTitle(button, showTime ? "\(engine.iconEmoji) \(engine.menuTimeString)" : engine.iconEmoji)
        case .symbol:
            setImage(button, symbolImage(engine.iconSymbol, label: engine.phaseLabel))
            setPosition(button, showTime ? .imageLeading : .imageOnly)
            setTitle(button, showTime ? " \(engine.menuTimeString)" : "")
        }
        // 커피 프레임이 실제로 재생 중일 때만 10Hz, 그 외엔 1Hz(시간 표시는 1초 단위면 충분).
        let animating = engine.settings.iconTheme == .coffee
            && CoffeeAnimation.hasFrames
            && !(engine.phase == .paused || engine.isAway || engine.phase == .scheduledRest)
        scheduleTitleTimer(interval: animating ? 0.125 : 1.0)
    }

    // MARK: - 상태아이템 대입 (바뀔 때만)
    //
    // 상태아이템은 값을 넣을 때마다 레이아웃을 다시 잡고 그림자 이미지를 새로 굽는다.
    // 10Hz 로 도는 갱신에서 안 바뀐 값까지 매번 넣으면 그게 고스란히 상시 CPU 다.
    // 정지 프레임 국면(일시정지·자리비움·고정 휴식)에서는 이 덕에 대입이 아예 일어나지 않는다.

    private func setImage(_ button: NSStatusBarButton, _ image: NSImage?) {
        if button.image !== image { button.image = image }
    }

    private func setTitle(_ button: NSStatusBarButton, _ title: String) {
        if button.title != title { button.title = title }
    }

    private func setPosition(_ button: NSStatusBarButton, _ position: NSControl.ImagePosition) {
        if button.imagePosition != position { button.imagePosition = position }
    }

    /// SF Symbol 도 매번 새로 만들면 같은 그림을 다시 굽게 된다. 이름당 한 번만 만든다.
    private func symbolImage(_ name: String, label: String) -> NSImage? {
        if let hit = symbolCache[name] { return hit }
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: label) else { return nil }
        symbolCache[name] = img
        return img
    }

    @objc private func togglePopover(_ sender: Any?) {
        engine.hideMenuHoverTip()   // 팝오버 열면 호버 팁은 치운다.
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.contentViewController = makePanelHost()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 패널 호스트를 새로 만든다. (팝오버를 열 때마다 호출)
    ///
    /// sizingOptions=[] : 콘텐츠 크기 기반 자동 제약 갱신을 끈다. (오버레이와 동일 이유 —
    /// macOS 26 강화된 Auto Layout 검증이 레이아웃 재진입을 크래시로 처리. 팝오버는
    /// contentSize 로 크기를 고정하므로 자동 사이징이 필요 없다.)
    private func makePanelHost() -> NSHostingController<PanelView> {
        let host = NSHostingController(rootView: PanelView(engine: engine))
        host.sizingOptions = []
        return host
    }

    /// 팝오버가 닫히면 뷰 계층을 통째로 버린다. (바깥 클릭으로 닫히는 .transient 도 여기로 온다)
    /// 닫히는 도중에 바로 떼면 AppKit 이 아직 그 뷰를 쓰고 있을 수 있어 다음 런루프로 미룬다.
    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.popover.contentViewController = nil
        }
    }

    // MARK: - 메뉴바 아이콘 호버 (시간 감춤 상태에서만 팁 표시)

    // 트래킹 영역은 owner 에게 `mouseEntered:`/`mouseExited:` 셀렉터를 보낸다.
    // AppDelegate 는 NSResponder 가 아니므로 셀렉터를 명시해 매핑한다.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        // 시간이 이미 보이거나 패널이 열려 있으면 팁 불필요.
        guard !engine.settings.showMenuBarTime, !popover.isShown,
              let frame = statusItem.button?.window?.frame else { return }
        engine.showMenuHoverTip(near: frame)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        engine.hideMenuHoverTip()
    }
}

@main
struct FikaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바 아이템은 AppDelegate 에서 직접 만든다.
        // 보이지 않는 더미 Settings 씬으로 App 의 Scene 요건만 충족.
        Settings { EmptyView() }
    }
}
