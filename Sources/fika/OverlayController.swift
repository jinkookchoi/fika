import AppKit
import SwiftUI
import FikaCore

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
        // 토스트와 같은 규격: 카드 440/500 + 여백 80/68 (여백이 같아야 스택 겹침 계산도 동일)
        let w: CGFloat = (engine.settings.timeNoticeBig ? 500 : 440) + 80
        let h: CGFloat = 64 + 68
        let f = screen.visibleFrame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h - 8, width: w, height: h)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        setHosted(win, WarningView(engine: engine))
        win.orderFront(nil)
        warningWindow = win
        restack()   // 이미 떠 있던 토스트를 배너 아래로 내림
    }

    func hideWarning() {
        warningWindow?.orderOut(nil)
        warningWindow = nil
        restack()   // 배너가 사라졌으니 토스트를 기준 위치로 올림
    }

    // MARK: - 토스트 알림 (잠깐 떴다 사라지는 알림 — 단일 진입점)

    /// 화면에 떠 있는 토스트 하나 (창 + 내용 + 소멸 타이머).
    private struct ActiveToast {
        let window: NSWindow
        let notice: Notice
        var timer: Timer?
    }

    /// 떠 있는 토스트들 — 최대 2장 스택. [0]이 기준 위치(먼저 뜬 것), 새 카드는 그 아래(우하단 배치면 위)에 쌓인다.
    private var toasts: [ActiveToast] = []
    /// 대기 1건: 두 자리가 다 찼을 때. 슬롯이 비면 표시하고, 유효기한이 지나면 조용히 폐기.
    private var pending: (notice: Notice, expires: Date)?
    /// 스택 시 창끼리 겹치는 높이 — 창의 상하 여백(각 ~34pt) 합 68에서 이만큼 빼면 카드 사이 시각 간격.
    /// 60 → 간격 ~8pt (사용자 피드백으로 조정: 24 멀다 → 16 → 그 절반).
    private static let stackOverlap: CGFloat = 60

    /// 모든 토스트 알림의 단일 진입점. 발화처(BreakEngine)는 Notice만 만들고,
    /// 표시(ToastView 템플릿·창 실측·로그 기록·소리)와 겹침 정책을 여기서 처리한다.
    /// 겹침: 자리(2장)가 있으면 스택으로 바로 표시, 다 찼으면 덜 급한 쪽과 비교해 교체 or 대기 1건.
    func post(_ notice: Notice) {
        // 같은 종류가 이미 떠 있으면 그 카드를 내리고 새 내용으로 (연타·문구 갱신 대비)
        if let dup = toasts.first(where: { $0.notice.logCategory == notice.logCategory }) {
            hide(dup.window)
        }
        let victim = toasts.max { $0.notice.priority < $1.notice.priority }   // 덜 급한 쪽(숫자 큰 쪽)
        let decision = NoticePolicy.decide(
            newPriority: notice.priority,
            warningHold: engine.isWarning && notice.waitsDuringWarning,
            currentPriority: toasts.count >= 2 ? victim?.notice.priority : nil)   // 자리 있으면 nil → 즉시 표시
        switch decision {
        case .show:
            display(notice)
        case .replace:
            if let victim { hide(victim.window) }   // 밀려난 토스트는 폐기(이미 보였으므로 재대기 안 함)
            display(notice)
        case .wait:
            if NoticePolicy.shouldReplacePending(newPriority: notice.priority,
                                                 pendingPriority: pending?.notice.priority) {
                pending = (notice, Date().addingTimeInterval(notice.validity))
                Log.debug("토스트 대기 (\(notice.logCategory))")
            } else {
                Log.debug("토스트 폐기 — 더 급한 대기건 있음 (\(notice.logCategory))")
            }
        }
    }

    /// 대기 중인 토스트를 표시할 수 있으면 표시한다. 엔진 tick(1초)마다 호출.
    func flushPending() {
        guard toasts.count < 2, let p = pending else { return }
        if Date() > p.expires {
            pending = nil
            Log.debug("대기 토스트 만료 폐기 (\(p.notice.logCategory))")
            return
        }
        if p.notice.requiresWorkingPhase && engine.phase != .working {
            pending = nil
            Log.debug("대기 토스트 폐기 — 작업 단계 아님 (\(p.notice.logCategory))")
            return
        }
        if engine.isWarning && p.notice.waitsDuringWarning { return }   // 예고 끝날 때까지 계속 대기
        pending = nil
        display(p.notice)
    }

    /// X 버튼 클로저가 "자기 창"을 닫을 수 있게 하는 약한 참조 상자 (뷰가 창보다 먼저 만들어져서 필요).
    private final class WindowBox { weak var window: NSWindow? }

    /// 토스트를 실제로 화면에 올린다 (창 실측·스택 위치·로그·소리·타이머).
    private func display(_ notice: Notice) {
        guard let screen = activeScreen else { return }
        let s = engine.settings
        let f = screen.visibleFrame

        let (spec, logMessage) = makeSpec(for: notice)
        let box = WindowBox()
        let view = ToastView(spec: spec,
                             big: s.timeNoticeBig,
                             motion: s.timeNoticeMotion,
                             pulse: s.timeNoticePulse,
                             onClose: { [weak self] in self?.hide(box.window) })

        // 폭 고정·높이 가변: 표시 전에 "측정 전용" 호스트로 한 번 실측해 창 프레임을 확정한다.
        // 주의: 표시용 호스트에 fittingSize를 물으면 사이징 제약이 생겨, 창에 얹는 순간
        // Auto Layout이 창을 카드 크기로 줄여버린다(여백 소실 → 등장 모션 때 좌우 잘림).
        // 그래서 측정은 창에 얹지 않는 일회용 뷰로만 하고, 표시는 setHosted(sizingOptions=[]) 경로로.
        let probe = NSHostingView(rootView: view)
        let fit = probe.fittingSize
        let w = (fit.width > 0 ? fit.width : (s.timeNoticeBig ? 500 : 440)) + 80   // 글로우+등장 모션 여백
        let h = min(max(fit.height, 60), 400) + 68

        // 이미 떠 있는 카드가 있으면 그 곁에 스택, 없으면 기준 위치(예고 배너가 있으면 그 아래).
        let rect = toasts.last.map { stackedFrame(anchor: $0.window.frame, w: w, h: h, in: f, position: s.timeNoticePosition) }
            ?? firstSlotFrame(w: w, h: h, in: f, position: s.timeNoticePosition)
        let win = makeWindow(frame: rect, level: .statusBar, passThrough: false)
        box.window = win
        // 루트뷰는 반드시 유연하게(maxWidth/Height ∞) 얹는다 — 고정 크기 루트를 그대로 얹으면
        // NSHostingView가 자신을 카드 크기로 줄여 글로우·등장 모션이 그 경계에서 잘린다.
        setHosted(win, view.frame(maxWidth: .infinity, maxHeight: .infinity))
        win.orderFront(nil)

        var toast = ActiveToast(window: win, notice: notice, timer: nil)
        let duration = notice.duration ?? max(2, s.timeNoticeDuration)
        toast.timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak win] _ in
            Task { @MainActor in self?.hide(win) }
        }
        toasts.append(toast)

        NotificationLog.shared.record(notice.logCategory, logMessage)
        if case .timeNotice = notice { Sound.playNotice(s.timeNoticeSound) }
        Log.debug("토스트 표시 (\(notice.logCategory), 스택 \(toasts.count)장)")
    }

    /// 기준 위치(1장째)의 창 프레임.
    private func primaryFrame(w: CGFloat, h: CGFloat, in f: NSRect, position: ToastPosition) -> NSRect {
        switch position {
        case .topCenter:   return NSRect(x: f.midX - w / 2, y: f.maxY - h - 16, width: w, height: h)
        case .center:      return NSRect(x: f.midX - w / 2, y: f.midY - h / 2,  width: w, height: h)
        case .bottomRight: return NSRect(x: f.maxX - w,     y: f.minY + 8,      width: w, height: h)
        }
    }

    /// 1장째가 실제로 앉을 자리 — 상단 중앙 배치에서 예고 배너가 떠 있으면 그 아래로 내려간다.
    /// (배너 창도 토스트와 같은 여백 규격이라 겹침값을 그대로 쓴다)
    private func firstSlotFrame(w: CGFloat, h: CGFloat, in f: NSRect, position: ToastPosition) -> NSRect {
        if position == .topCenter, let banner = warningWindow?.frame {
            return stackedFrame(anchor: banner, w: w, h: h, in: f, position: position)
        }
        return primaryFrame(w: w, h: h, in: f, position: position)
    }

    /// 이미 떠 있는 창(anchor) 곁에 쌓이는 위치 — 상단/중앙 배치는 아래로, 우하단 배치는 위로.
    private func stackedFrame(anchor: NSRect, w: CGFloat, h: CGFloat, in f: NSRect, position: ToastPosition) -> NSRect {
        switch position {
        case .topCenter, .center:
            return NSRect(x: f.midX - w / 2, y: anchor.minY - h + Self.stackOverlap, width: w, height: h)
        case .bottomRight:
            return NSRect(x: f.maxX - w, y: anchor.maxY - Self.stackOverlap, width: w, height: h)
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
            var spec = ToastSpec(cut: "work", emoji: "☕",
                                 caption: "잠깐, 이거 해볼까요?", title: tip)
            if engine.phase == .working {   // 동작 알림에 남은 시간을 곁들임 (남은시간 알림을 안 켜도 보이게)
                spec.subtitle = "휴식까지 \(engine.remainingMinutesRounded)분"
            }
            return (spec, tip)

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
                spec.buttonAction = { [weak self] in self?.engine.quietForToday(); self?.hideAllToasts() }
            }
            return (spec, title)

        case .scheduledRest(let title, let subtitle, _):
            return (ToastSpec(cut: "resting", emoji: "☕", title: title, subtitle: subtitle), title)
        }
    }

    /// 특정 토스트를 내린다 (X 버튼·소멸 타이머·교체). 남은 카드는 기준 위치로 미끄러진다.
    private func hide(_ window: NSWindow?) {
        guard let window, let idx = toasts.firstIndex(where: { $0.window === window }) else { return }
        toasts[idx].timer?.invalidate()
        toasts.remove(at: idx)
        fadeOut(window)
        restack()
    }

    /// 모든 토스트를 내린다 ("오늘은 그만" 버튼 등).
    func hideAllToasts() {
        for t in toasts {
            t.timer?.invalidate()
            fadeOut(t.window)
        }
        toasts.removeAll()
    }

    private func fadeOut(_ win: NSWindow) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            win.animator().alphaValue = 0
        }, completionHandler: { win.orderOut(nil) })
    }

    /// 떠 있는 토스트들을 제자리(배너 아래 → 스택 순서)로 이동. 같은 크기의 "이동"만 한다 —
    /// 표시 후 리사이즈는 macOS 26 크래시 함정이라 절대 안 한다.
    private func restack() {
        guard let f = toasts.first?.window.screen?.visibleFrame else { return }
        let position = engine.settings.timeNoticePosition
        var anchor: NSRect?
        for t in toasts {
            let size = t.window.frame.size
            let target = anchor.map { stackedFrame(anchor: $0, w: size.width, h: size.height, in: f, position: position) }
                ?? firstSlotFrame(w: size.width, h: size.height, in: f, position: position)
            if target != t.window.frame {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    t.window.animator().setFrame(target, display: true)
                }
            }
            anchor = target
        }
    }

    /// 개발용(FIKA_TEST_TOAST): 떠 있는 토스트·예고 배너 창들을 하나의 PNG로 저장 — 화면 캡처 권한 없이 시각 확인.
    func snapshotToast(to path: String) {
        var windows = toasts.map(\.window)
        if let banner = warningWindow { windows.insert(banner, at: 0) }
        guard !windows.isEmpty else { return }
        let frames = windows.map(\.frame)
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let img = NSImage(size: union.size)
        img.lockFocus()
        for win in windows {
            guard let v = win.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            // rep.draw는 copy 합성이라 위 창의 투명 여백이 아래 창을 지운다 → sourceOver로.
            let piece = NSImage(size: v.bounds.size)
            piece.addRepresentation(rep)
            piece.draw(in: NSRect(x: win.frame.minX - union.minX,
                                  y: win.frame.minY - union.minY,
                                  width: win.frame.width, height: win.frame.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let outRep = NSBitmapImageRep(data: tiff),
              let png = outRep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
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
