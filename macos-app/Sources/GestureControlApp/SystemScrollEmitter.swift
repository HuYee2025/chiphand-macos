import AppKit
import ApplicationServices
import GestureControlCore

protocol ScrollEmitting {
    func emitContinuous(normalizedDelta: Double, to processID: pid_t)
    func emitPage(_ direction: PageDirection, to processID: pid_t)
}

final class SystemScrollEmitter: ScrollEmitting {
    private let queue = DispatchQueue(label: "com.huyee.gesture-control.scroll")

    func emitContinuous(normalizedDelta: Double, to processID: pid_t) {
        let height = Double(CGDisplayPixelsHigh(CGMainDisplayID()))
        let revealPixels = max(-120, min(120, normalizedDelta * height * 1.8))
        post(revealPixels: revealPixels, to: processID)
    }

    func emitPage(_ direction: PageDirection, to processID: pid_t) {
        let height = Double(CGDisplayPixelsHigh(CGMainDisplayID()))
        let total = height * 0.75 * (direction == .down ? 1 : -1)
        let steps = 12
        queue.async { [weak self] in
            for index in 0..<steps {
                let phase = Double(index + 1) / Double(steps)
                let weight = sin(phase * .pi)
                let denominator = 7.595754112725151 // Sum of sin(i*pi/12), i=1...12.
                self?.post(revealPixels: total * weight / denominator, to: processID)
                Thread.sleep(forTimeInterval: 0.014)
            }
        }
    }

    private func post(revealPixels: Double, to processID: pid_t) {
        guard AXIsProcessTrusted(), processID > 0 else { return }
        // Quartz positive wheel values move toward earlier content. The public
        // API uses positive values to mean "reveal content below", hence minus.
        let wheelValue = Int32(max(Double(Int32.min), min(Double(Int32.max), -revealPixels.rounded())))
        let source = CGEventSource(stateID: .hidSystemState)
        guard wheelValue != 0,
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: wheelValue,
                wheel2: 0,
                wheel3: 0
              ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.location = targetLocation(for: processID)
            ?? CGEvent(source: nil)?.location
            ?? .zero
        // A wheel event is a device-class event. Posting it directly to a PID
        // can be ignored by Chromium; inject it at the HID event tap so macOS
        // routes it like real mouse/trackpad input to the target window.
        event.post(tap: .cghidEventTap)
    }

    private func targetLocation(for processID: pid_t) -> CGPoint? {
        let application = AXUIElementCreateApplication(processID)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let window = windowValue else { return nil }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }
}
