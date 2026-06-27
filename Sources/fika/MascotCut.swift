import SwiftUI
import AppKit

/// 화면 UI(예고 배너·휴식 오버레이·토스트)에서 쓰는 커피 마스코트 정지 컷.
/// `.app/Contents/Resources/cuts/<name>.png` 의 고해상도 투명 이미지를 로드한다.
enum MascotCut {
    /// work / warning / resting / done
    static func image(_ name: String) -> Image? {
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("cuts", isDirectory: true)
                .appendingPathComponent("\(name).png"),
              let ns = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: ns)
    }
}
