import AppKit

/// 메뉴바 커피 잔 애니메이션을 미리 만든 프레임(PNG 시퀀스)으로 재생한다.
/// 상태별 클립이 `.app/Contents/Resources/coffee/<clip>/frame_NNN.png` 에 들어있고
/// 앱 시작 시 한 번 로드해 메모리에 상주시킨다.
/// (절차적 `CoffeeIcon` 과 달리 작업 진행도와는 연동되지 않는 루프 영상)
enum CoffeeAnimation {
    /// 상태별 클립. (작업/휴식=work, 곧 휴식=warning, 복귀 대기=done)
    enum Clip: String { case work, warning, done }

    /// 메뉴바에 표시할 한 변 크기(pt). 레티나에선 2x 로 그려진다.
    private static let glyphSize = NSSize(width: 20, height: 20)

    private static let clips: [Clip: [NSImage]] = {
        var m: [Clip: [NSImage]] = [:]
        for c in [Clip.work, .warning, .done] { m[c] = load(c) }
        return m
    }()
    /// 클립이 바뀌어도 자연스럽게 이어지도록 인덱스는 공유한다.
    private static var index = 0

    static var hasFrames: Bool { !(clips[.work]?.isEmpty ?? true) }

    /// 다음 프레임을 돌려준다. (호출 주기가 곧 재생 속도)
    /// 해당 클립이 비어 있으면 work 로 폴백한다.
    static func next(_ clip: Clip) -> NSImage? {
        let frames = clips[clip]?.isEmpty == false ? clips[clip]! : (clips[.work] ?? [])
        guard !frames.isEmpty else { return nil }
        let img = frames[index % frames.count]
        index += 1
        return img
    }

    /// 정지 프레임(첫 장). 일시정지·자리비움 표시용.
    static func still(_ clip: Clip) -> NSImage? {
        (clips[clip]?.isEmpty == false ? clips[clip] : clips[.work])?.first
    }

    private static func load(_ clip: Clip) -> [NSImage] {
        guard let dir = Bundle.main.resourceURL?
            .appendingPathComponent("coffee", isDirectory: true)
            .appendingPathComponent(clip.rawValue, isDirectory: true) else { return [] }
        var images: [NSImage] = []
        var i = 0
        while true {
            let url = dir.appendingPathComponent(String(format: "frame_%03d.png", i))
            guard let img = NSImage(contentsOf: url) else { break }
            img.size = glyphSize
            img.isTemplate = false   // 컬러 유지
            images.append(img)
            i += 1
        }
        return images
    }
}
