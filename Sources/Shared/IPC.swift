import Foundation

/// Messages between the app and the engine. DistributedNotificationCenter is enough:
/// both processes run in the same user session and neither is sandboxed.
enum IPC {
    enum Name: String {
        case settingsChanged = "com.keyboost.settings-changed"
        case statusChanged   = "com.keyboost.status-changed"
    }

    static func post(_ name: Name) {
        DistributedNotificationCenter.default()
            .postNotificationName(Notification.Name(name.rawValue), object: nil,
                                  userInfo: nil, deliverImmediately: true)
    }

    static func observe(_ name: Name, handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default()
            .addObserver(forName: Notification.Name(name.rawValue), object: nil, queue: .main) { _ in
                handler()
            }
    }
}
