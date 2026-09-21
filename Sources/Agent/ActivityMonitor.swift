import CoreGraphics
import Foundation

/// How long since you last touched the machine.
///
/// Uses `CGEventSourceSecondsSinceLastEventType`, a system-wide idle counter:
/// **this is not an event tap**. It cannot read keystroke content and needs no
/// Accessibility permission.
enum ActivityMonitor {
    private static func seconds(_ type: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    private static let keyboardSignals: [CGEventType] = [.keyDown, .flagsChanged]
    private static let pointingSignals: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]

    /// Seconds since the last activity relevant to this kind of device.
    /// A keyboard should not stay boosted just because you moved the trackpad.
    static func idleSeconds(for kind: DeviceKind) -> Double {
        let signals: [CGEventType]
        switch kind {
        case .keyboard: signals = keyboardSignals
        case .pointing: signals = pointingSignals
        case .other:    signals = keyboardSignals + pointingSignals
        }
        return signals.map(seconds).min() ?? .greatestFiniteMagnitude
    }
}
