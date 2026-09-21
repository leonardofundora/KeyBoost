import Foundation

/// Avisos entre la app y el motor. DistributedNotificationCenter basta:
/// ambos procesos corren en la misma sesión de usuario y no hay sandbox.
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
