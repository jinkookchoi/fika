import Foundation
import IOKit

enum SystemIdle {
    /// 마지막 HID 입력 이후 경과한 초.
    /// IOHIDSystem 의 HIDIdleTime 을 읽으므로 키보드·마우스·트랙패드·조이스틱 등
    /// 모든 HID 장치의 입력을 포함한다. (권한 불필요, 입력 내용은 읽지 않음)
    static func seconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOHIDSystem"),
                                           &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let idle = dict["HIDIdleTime"] as? NSNumber else {
            return 0
        }
        return idle.doubleValue / 1_000_000_000  // 나노초 → 초
    }
}
