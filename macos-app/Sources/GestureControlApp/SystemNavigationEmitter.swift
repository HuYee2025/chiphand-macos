import ApplicationServices
import GestureControlCore

protocol NavigationEmitting {
    func emit(_ direction: NavigationDirection)
}

final class SystemNavigationEmitter: NavigationEmitting {
    private let queue = DispatchQueue(label: "com.huyee.gesture-control.navigation")

    func emit(_ direction: NavigationDirection) {
        guard AXIsProcessTrusted() else { return }
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyCode: CGKeyCode = direction == .back
                ? 33 // kVK_ANSI_LeftBracket
                : 30 // kVK_ANSI_RightBracket
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
            ) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.025)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
