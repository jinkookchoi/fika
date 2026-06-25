import AppKit

/// 버튼 클릭을 받기 위해 키 윈도우가 될 수 있는 테두리 없는 윈도우.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension NSWindow {
    /// 모든 스페이스/전체화면 위에 떠 있도록 공통 설정.
    func configureAsOverlay(level: NSWindow.Level, passThrough: Bool) {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        self.level = level
        ignoresMouseEvents = passThrough
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}
