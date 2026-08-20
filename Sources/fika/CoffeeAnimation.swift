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
            images.append(flatten(img))
            i += 1
        }
        return images
    }

    /// 메뉴바 표시 크기 그대로의 비트맵 한 장으로 미리 구워둔다.
    ///
    /// 원본 프레임 PNG 는 글리프(20pt)보다 훨씬 크다. `img.size` 만 줄여서 넘기면 이미지는
    /// 원본 rep 을 그대로 들고 있어서, 상태아이템에 대입할 때마다 AppKit 이 20pt 로 다시
    /// 리샘플하고 그림자 이미지(`NSCreateStatusItemShadowImage`)를 새로 굽는다 — 그게 10Hz 로
    /// 반복되면 그대로 상시 CPU 가 된다. 표시 배율로 미리 구워두면 이후엔 그대로 옮겨 그린다.
    /// (표시 크기·모양은 그대로라 화면상 인상은 달라지지 않는다.)
    private static func flatten(_ src: NSImage) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(glyphSize.width * scale),
                pixelsHigh: Int(glyphSize.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            // 비트맵을 못 만들면 예전 방식으로 폴백(느릴 뿐, 그림은 같다).
            src.size = glyphSize
            src.isTemplate = false
            return src
        }
        rep.size = glyphSize   // 픽셀은 2x, 논리 크기는 20pt

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: NSRect(origin: .zero, size: glyphSize),
                 from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: glyphSize)
        out.addRepresentation(rep)
        out.isTemplate = false   // 컬러 유지
        return out
    }
}
