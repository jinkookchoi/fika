import AppKit
import SwiftUI

/// 휴식 오버레이와 예고 배너 윈도우의 생성/소멸을 담당.
@MainActor
final class OverlayController {
    private unowned let engine: BreakEngine

    private var breakWindows: [NSWindow] = []
    private var currentStyle: BreakStyle?
    private var warningWindow: NSWindow?
    private var toastWindow: NSWindow?
    private var toastTimer: Timer?

    init(engine: BreakEngine) {
        self.engine = engine
    }

    // MARK: - 휴식 오버레이

    func showBreak(style: BreakStyle) {
        if !breakWindows.isEmpty && currentStyle == style { return }
        hideBreak()
        currentStyle = style

        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens.first
        Log.debug("휴식 오버레이 표시 (style=\(style), 화면 \(screens.count)개)")

        switch style {
        case .fullscreen:
            for screen in screens {
                let isMain = (screen == mainScreen)
                let w = makeWindow(frame: screen.frame,
                                   level: .screenSaver,
                                   passThrough: false)
                setHosted(w, BreakView(engine: engine, fullscreen: true, showCard: isMain))
                w.makeKeyAndOrderFront(nil)
                breakWindows.append(w)
            }
            NSApp.activate(ignoringOtherApps: true)

        case .soft:
            // 가장자리 글로우: 클릭 통과
            for screen in screens {
                let glow = makeWindow(frame: screen.frame,
                                      level: .floating,
                                      passThrough: true)
                setHosted(glow, VignetteView(engine: engine))
                glow.orderFront(nil)
                breakWindows.append(glow)
            }
            // 조작 카드: 메인 화면 상단, 클릭 가능
            if let screen = mainScreen {
                let cardW: CGFloat = 360, cardH: CGFloat = 220
                let f = screen.visibleFrame
                let rect = NSRect(x: f.midX - cardW / 2,
                                  y: f.maxY - cardH - 24,
                                  width: cardW, height: cardH)
                let card = makeWindow(frame: rect, level: .floating, passThrough: false)
                setHosted(card, BreakView(engine: engine, fullscreen: false, showCard: true))
                card.makeKeyAndOrderFront(nil)
                breakWindows.append(card)
            }
        }
    }

    func hideBreak() {
        guard !breakWindows.isEmpty else { return }
        breakWindows.forEach { $0.orderOut(nil) }
        breakWindows.removeAll()
        currentStyle = nil
        Log.debug("휴식 오버레이 숨김")
    }

    // MARK: - 예고 배너

    func showWarning() {
        if warningWindow != nil { return }
        guard let screen = NSScreen.main else { return }
        let w: CGFloat = 320, h: CGFloat = 72
        let f = screen.visibleFrame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h - 16, width: w, height: h)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        setHosted(win, WarningView(engine: engine))
        win.orderFront(nil)
        warningWindow = win
    }

    func hideWarning() {
        warningWindow?.orderOut(nil)
        warningWindow = nil
    }

    // MARK: - 작업 시작 토스트 (잠깐 떴다 사라지는 알림)

    func showStartToast() {
        hideStartToast()
        guard let screen = NSScreen.main else { return }
        let w: CGFloat = 520, h: CGFloat = 140   // 토스트 + 글로우 여백
        let f = screen.visibleFrame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h - 16, width: w, height: h)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        setHosted(win, StartToastView(engine: engine, onClose: { [weak self] in self?.hideStartToast() }))
        win.orderFront(nil)
        toastWindow = win
        Log.debug("작업 시작 토스트 표시")
        toastTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideStartToast() }
        }
    }

    func hideStartToast() {
        toastTimer?.invalidate()
        toastTimer = nil
        guard let win = toastWindow else { return }
        toastWindow = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            win.animator().alphaValue = 0
        }, completionHandler: { win.orderOut(nil) })
    }

    /// 작업 중 마이크로 브레이크 동작 알림. (클릭 통과, 잠깐 떴다 사라짐)
    func showStretchToast(_ text: String) {
        hideStartToast()
        guard let screen = NSScreen.main else { return }
        let w: CGFloat = 520, h: CGFloat = 140   // 토스트(최대 440) + 글로우 여백
        let f = screen.visibleFrame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h - 16, width: w, height: h)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        setHosted(win, StretchToastView(text: text, onClose: { [weak self] in self?.hideStartToast() }))
        win.orderFront(nil)
        toastWindow = win
        toastTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideStartToast() }
        }
    }

    // MARK: -

    /// SwiftUI 뷰를 borderless 창의 contentView 로 얹는다.
    /// `sizingOptions = []` 로 NSHostingView 가 창의 콘텐츠 크기 제약을 자동 갱신하지
    /// 않게 막는다. (그 자동 갱신이 레이아웃 패스 중 재진입 예외를 일으켜 크래시했음 —
    /// 특히 sleep/wake 후 디스플레이 재계산 시. 오버레이는 고정 크기/전체화면이라 자동
    /// 사이징이 애초에 필요 없다.)
    private func setHosted<V: View>(_ window: NSWindow, _ view: V) {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    private func makeWindow(frame: NSRect, level: NSWindow.Level, passThrough: Bool) -> NSWindow {
        let w = KeyableWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        w.setFrame(frame, display: false)
        w.configureAsOverlay(level: level, passThrough: passThrough)
        return w
    }
}
