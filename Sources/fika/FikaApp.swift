import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = BreakEngine.shared
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var titleTimer: Timer?
    /// 김 애니메이션 위상 (커피 테마용)
    private var steamPhase: Double = 0

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
        // sizingOptions=[] : 콘텐츠 크기 기반 자동 제약 갱신을 끈다. (오버레이와 동일 이유 —
        // macOS 26 강화된 Auto Layout 검증이 레이아웃 재진입을 크래시로 처리. 팝오버는
        // contentSize 로 크기를 고정하므로 자동 사이징이 필요 없다.)
        let panelHost = NSHostingController(rootView: PanelView(engine: engine))
        panelHost.sizingOptions = []
        popover.contentViewController = panelHost

        // 메뉴바 갱신 (커피 애니메이션 프레임 재생 ~10fps)
        titleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        steamPhase += 0.6
        let showTime = engine.settings.showMenuBarTime
        switch engine.settings.iconTheme {
        case .coffee:
            // 상태별 영상 마스코트 프레임 재생. (일시정지·자리비움이면 정지 프레임)
            let clip: CoffeeAnimation.Clip =
                engine.phase == .breakHold ? .done
                : (engine.phase == .working && engine.isWarning) ? .warning
                : .work
            let frozen = engine.phase == .paused || engine.isAway
            button.image = frozen ? CoffeeAnimation.still(clip) : CoffeeAnimation.next(clip)
            button.imagePosition = showTime ? .imageLeading : .imageOnly
            button.title = showTime ? " \(engine.menuTimeString)" : ""
        case .emoji:
            button.image = nil
            button.title = showTime ? "\(engine.iconEmoji) \(engine.menuTimeString)" : engine.iconEmoji
        case .symbol:
            button.image = NSImage(systemSymbolName: engine.iconSymbol, accessibilityDescription: engine.phaseLabel)
            button.imagePosition = showTime ? .imageLeading : .imageOnly
            button.title = showTime ? " \(engine.menuTimeString)" : ""
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        engine.hideMenuHoverTip()   // 팝오버 열면 호버 팁은 치운다.
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
