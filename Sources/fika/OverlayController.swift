import AppKit
import SwiftUI

/// 휴식 오버레이와 예고 배너 윈도우의 생성/소멸을 담당.
@MainActor
final class OverlayController {
    private unowned let engine: BreakEngine

    private var breakWindows: [NSWindow] = []
    private var currentStyle: BreakStyle?
    private var warningWindow: NSWindow?

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

        switch style {
        case .fullscreen:
            for screen in screens {
                let isMain = (screen == mainScreen)
                let w = makeWindow(frame: screen.frame,
                                   level: .screenSaver,
                                   passThrough: false)
                w.contentView = NSHostingView(
                    rootView: BreakView(engine: engine, fullscreen: true, showCard: isMain)
                )
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
                glow.contentView = NSHostingView(rootView: VignetteView(engine: engine))
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
                card.contentView = NSHostingView(
                    rootView: BreakView(engine: engine, fullscreen: false, showCard: true)
                )
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
    }

    // MARK: - 예고 배너

    func showWarning() {
        if warningWindow != nil { return }
        guard let screen = NSScreen.main else { return }
        let w: CGFloat = 320, h: CGFloat = 72
        let f = screen.visibleFrame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h - 16, width: w, height: h)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        win.contentView = NSHostingView(rootView: WarningView(engine: engine))
        win.orderFront(nil)
        warningWindow = win
    }

    func hideWarning() {
        warningWindow?.orderOut(nil)
        warningWindow = nil
    }

    // MARK: -

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
