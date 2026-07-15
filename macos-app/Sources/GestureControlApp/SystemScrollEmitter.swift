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
        guard wheelValue != 0,
              let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: wheelValue,
                wheel2: 0,
                wheel3: 0
              ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.postToPid(processID)
    }
}
