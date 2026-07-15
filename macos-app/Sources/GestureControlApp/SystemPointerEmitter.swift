import ApplicationServices
import CoreGraphics
import GestureControlCore

protocol PointerEmitting {
    func move(to point: NormalizedPoint)
    func click(at point: NormalizedPoint)
}

final class SystemPointerEmitter: PointerEmitting {
    private let queue = DispatchQueue(label: "com.huyee.gesture-control.pointer")
    private var lastLocation: CGPoint?

    func move(to point: NormalizedPoint) {
        guard AXIsProcessTrusted() else { return }
        let location = screenLocation(for: point)
        if let lastLocation, hypot(location.x - lastLocation.x, location.y - lastLocation.y) < 4 {
            return
        }
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
        lastLocation = location
    }

    func click(at point: NormalizedPoint) {
        guard AXIsProcessTrusted() else { return }
        let location = screenLocation(for: point)
        lastLocation = location
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: location,
                mouseButton: .left
            ), let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else { return }
            down.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.035)
            up.post(tap: .cghidEventTap)
        }
    }

    private func screenLocation(for point: NormalizedPoint) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let x = max(0, min(1, point.x))
        let y = max(0, min(1, point.y))
        return CGPoint(
            x: bounds.minX + x * bounds.width,
            y: bounds.minY + (1 - y) * bounds.height
        )
    }
}
