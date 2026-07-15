import ApplicationServices

protocol NavigationEmitting {
    func emitBack()
}

final class SystemNavigationEmitter: NavigationEmitting {
    private let queue = DispatchQueue(label: "com.huyee.gesture-control.navigation")

    func emitBack() {
        guard AXIsProcessTrusted() else { return }
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyCode: CGKeyCode = 33 // kVK_ANSI_LeftBracket
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
