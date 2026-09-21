import CoreGraphics
import Foundation

/// Cuánto hace que no tocas el equipo.
///
/// Usa `CGEventSourceSecondsSinceLastEventType`, que es un contador del sistema:
/// **no es un event tap**, no lee el contenido de las pulsaciones y no necesita
/// permiso de Accesibilidad.
enum ActivityMonitor {
    private static func seconds(_ type: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    private static let keyboardSignals: [CGEventType] = [.keyDown, .flagsChanged]
    private static let pointingSignals: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]

    /// Segundos desde la última actividad relevante para este tipo de dispositivo.
    /// Un teclado no debe seguir en turbo porque muevas el trackpad.
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
