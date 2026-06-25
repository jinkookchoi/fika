import Foundation
import ServiceManagement

/// 로그인 시 자동 실행 토글.
enum LoginItem {
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("fika: login item toggle failed: \(error)")
        }
    }
}
