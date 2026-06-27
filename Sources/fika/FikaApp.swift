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
        }
        updateButton()

        // 팝오버 = 통합 패널
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 460)
        // sizingOptions=[] : 콘텐츠 크기 기반 자동 제약 갱신을 끈다. (오버레이와 동일 이유 —
        // macOS 26 강화된 Auto Layout 검증이 레이아웃 재진입을 크래시로 처리. 팝오버는
        // contentSize 로 크기를 고정하므로 자동 사이징이 필요 없다.)
        let panelHost = NSHostingController(rootView: PanelView(engine: engine))
        panelHost.sizingOptions = []
        popover.contentViewController = panelHost

        // 메뉴바 갱신 (커피 김이 부드럽게 흔들리도록 짧은 주기로 다시 그린다)
        titleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        steamPhase += 0.6
        let showTime = engine.settings.showMenuBarTime
        switch engine.settings.iconTheme {
        case .coffee:
            button.image = CoffeeIcon.image(
                level: engine.coffeeLevel,
                steamPhase: steamPhase,
                away: engine.isAway,
                paused: engine.phase == .paused,
                warning: engine.isWarning ? engine.warningIntensity : 0)
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
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
