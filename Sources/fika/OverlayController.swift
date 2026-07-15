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
        guard let screen = activeScreen else { return }
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

    // MARK: - 토스트 알림 (잠깐 떴다 사라지는 알림 — 단일 진입점)

    /// 모든 토스트 알림의 단일 진입점. 발화처(BreakEngine)는 Notice만 만들고,
    /// 표시(ToastView 템플릿·창 실측·로그 기록·소리)는 전부 여기서 처리한다.
    /// 겹침은 기존과 동일하게 "떠 있던 토스트를 내리고 즉시 표시" — 우선순위/대기 정책은 커밋 ③에서.
    func post(_ notice: Notice) {
        hideToast()
        guard let screen = activeScreen else { return }
        let s = engine.settings
        let f = screen.visibleFrame

        let (spec, logMessage) = makeSpec(for: notice)
        let view = ToastView(spec: spec,
                             big: s.timeNoticeBig,
                             motion: s.timeNoticeMotion,
                             pulse: s.timeNoticePulse,
                             onClose: { [weak self] in self?.hideToast() })

        // 폭 고정·높이 가변: 표시 전에 "측정 전용" 호스트로 한 번 실측해 창 프레임을 확정한다.
        // 주의: 표시용 호스트에 fittingSize를 물으면 사이징 제약이 생겨, 창에 얹는 순간
        // Auto Layout이 창을 카드 크기로 줄여버린다(여백 소실 → 등장 모션 때 좌우 잘림).
        // 그래서 측정은 창에 얹지 않는 일회용 뷰로만 하고, 표시는 setHosted(sizingOptions=[]) 경로로.
        let probe = NSHostingView(rootView: view)
        let fit = probe.fittingSize
        let w = (fit.width > 0 ? fit.width : (s.timeNoticeBig ? 500 : 440)) + 80   // 글로우+등장 모션 여백
        let h = min(max(fit.height, 60), 400) + 68

        let rect: NSRect
        switch s.timeNoticePosition {   // 표시 위치: 전 토스트 공통 설정
        case .topCenter:   rect = NSRect(x: f.midX - w / 2, y: f.maxY - h - 16, width: w, height: h)
        case .center:      rect = NSRect(x: f.midX - w / 2, y: f.midY - h / 2,  width: w, height: h)
        case .bottomRight: rect = NSRect(x: f.maxX - w,     y: f.minY + 8,      width: w, height: h)
        }
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        // 루트뷰는 반드시 유연하게(maxWidth/Height ∞) 얹는다 — 고정 크기 루트를 그대로 얹으면
        // NSHostingView가 자신을 카드 크기로 줄여 글로우·등장 모션이 그 경계에서 잘린다.
        setHosted(win, view.frame(maxWidth: .infinity, maxHeight: .infinity))
        win.orderFront(nil)
        toastWindow = win

        NotificationLog.shared.record(notice.logCategory, logMessage)
        if case .timeNotice = notice { Sound.playNotice(s.timeNoticeSound) }
        Log.debug("토스트 표시 (\(notice.logCategory))")

        let duration = notice.duration ?? max(2, s.timeNoticeDuration)
        toastTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hideToast() }
        }
    }

    /// Notice → 토스트 내용(spec)과 알림 이력 문구.
    private func makeSpec(for notice: Notice) -> (ToastSpec, String) {
        let s = engine.settings
        switch notice {
        case .start:
            return (ToastSpec(cut: "work", emoji: "🌱", theme: .green,
                              caption: "이제 시작해볼까요?",
                              title: "\(Int(s.workMinutes))분, 열심히 해봐요"),
                    "이제 시작해볼까요?")

        case .stretch(let tip):
            return (ToastSpec(cut: "work", emoji: "☕",
                              caption: "잠깐, 이거 해볼까요?", title: tip),
                    tip)

        case .timeNotice(let final):
            let mins = engine.remainingMinutesRounded
            var spec = ToastSpec(cut: engine.mascotCut, emoji: "☕",
                                 theme: s.timeNoticeWarm ? .amber : .warm,
                                 caption: final ? "곧 휴식이에요" : "아직 집중 중이에요",
                                 title: final ? "잠깐 정리하고 일어날 준비해요" : "휴식까지 \(mins)분 남았어요")
            if s.timeNoticeHero && !final {   // 최종 알림은 항상 문구
                spec.heroNumber = "\(mins)분"
                spec.heroSuffix = " 뒤 휴식이에요"
            }
            if !final {
                // 커피잔으로 남은/지난 시간 시각화. 기본 1잔=5분, 긴 세션은 단위를 키워
                // 항상 12잔 이내로 유지(작업 시간 설정 최대 180분 → 5분 단위면 36잔이라 한 줄에 안 들어감).
                let sessionMin = engine.phaseDuration / 60
                let unitMin: Double = sessionMin <= 60 ? 5 : (sessionMin <= 120 ? 10 : 15)
                let per = unitMin * 60
                let total = min(14, max(1, Int((engine.phaseDuration / per).rounded(.up))))   // 14 = snooze 연장 방어
                let filled = min(total, max(0, Int((engine.remaining / per).rounded(.up))))
                spec.cups = (filled: filled, total: total)
            }
            return (spec, final ? "곧 휴식이에요" : "휴식까지 \(mins)분 남았어요")

        case .shutdown(let title, let subtitle, let stop):
            var spec = ToastSpec(cut: "done", emoji: "☕", title: title, subtitle: subtitle)
            if stop {
                spec.buttonLabel = "오늘은 그만"
                spec.buttonAction = { [weak self] in self?.engine.quietForToday(); self?.hideToast() }
            }
            return (spec, title)

        case .scheduledRest(let title, let subtitle):
            return (ToastSpec(cut: "resting", emoji: "☕", title: title, subtitle: subtitle), title)
        }
    }

    func hideToast() {
        toastTimer?.invalidate()
        toastTimer = nil
        guard let win = toastWindow else { return }
        toastWindow = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            win.animator().alphaValue = 0
        }, completionHandler: { win.orderOut(nil) })
    }

    /// 토스트가 지금 떠 있는지. (서로 겹치지 않게 양보 판단용)
    var isToastVisible: Bool { toastWindow != nil }

    /// 개발용(FIKA_TEST_TOAST): 현재 토스트 창을 PNG로 저장 — 화면 캡처 권한 없이 시각 확인.
    func snapshotToast(to path: String) {
        guard let view = toastWindow?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - 메뉴바 호버 팁 (시간 감춤 상태에서 아이콘에 마우스 올리면)

    private var hoverTipWindow: NSWindow?

    /// `anchor` 는 메뉴바 상태아이템의 화면 프레임. 그 바로 아래 중앙에 팁을 띄운다.
    func showHoverTip(near anchor: NSRect) {
        if hoverTipWindow != nil { return }   // 이미 떠 있으면 유지(깜빡임 방지)
        let w: CGFloat = 160, h: CGFloat = 56
        let rect = NSRect(x: anchor.midX - w / 2, y: anchor.minY - h - 2, width: w, height: h)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: true)
        setHosted(win, HoverTipView(engine: engine))
        win.orderFront(nil)
        hoverTipWindow = win
    }

    func hideHoverTip() {
        hoverTipWindow?.orderOut(nil)
        hoverTipWindow = nil
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

    /// 토스트·예고 배너를 띄울 화면. 메뉴바 전용(accessory) 앱은 키 윈도우가 없어
    /// `NSScreen.main`이 사실상 내장 디스플레이로 고정된다 → 외장 모니터에서 일하면 알림을 못 본다.
    /// 그래서 **마우스 커서가 있는 화면**("지금 보고 있는" 화면)에 띄운다. 없으면 주 화면 폴백.
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
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
