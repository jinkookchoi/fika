import SwiftUI
import AppKit

/// 화면 UI(예고 배너·휴식 오버레이·토스트)에서 쓰는 커피 마스코트 정지 컷.
/// `.app/Contents/Resources/cuts/<name>.png` 의 고해상도 투명 이미지를 로드한다.
enum MascotCut {
    /// 한 번 읽은 컷은 메모리에 들고 있는다.
    ///
    /// `NSImage(contentsOf:)` 는 `NSImage(named:)` 와 달리 캐시하지 않아서,
    /// 캐시가 없으면 호출할 때마다 파일시스템 stat + PNG 디코딩이 새로 일어난다.
    /// 호출처가 전부 SwiftUI body(진행 링·오버레이·토스트)라 초당 수십 번 불리므로
    /// 그대로 두면 그게 곧 상시 CPU 점유가 된다.
    /// 컷은 work / warning / resting / done 4종뿐이라 통째로 들고 있어도 가볍다.
    /// 없는 컷(nil)도 캐시해서 매번 디스크를 다시 뒤지지 않게 한다.
    @MainActor private static var cache: [String: Image?] = [:]

    /// work / warning / resting / done
    @MainActor
    static func image(_ name: String) -> Image? {
        if let hit = cache[name] { return hit }
        let loaded = load(name)
        cache[name] = loaded
        return loaded
    }

    private static func load(_ name: String) -> Image? {
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("cuts", isDirectory: true)
                .appendingPathComponent("\(name).png"),
              let ns = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: ns)
    }
}
