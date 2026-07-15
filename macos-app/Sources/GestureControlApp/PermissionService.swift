import AppKit
import ApplicationServices
import AVFoundation

enum PermissionState: String {
    case unknown = "未请求"
    case granted = "已允许"
    case denied = "未允许"
}

enum PermissionService {
    static var cameraState: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    static var accessibilityState: PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    static func requestCamera() async -> Bool {
        if cameraState == .granted { return true }
        guard cameraState == .unknown else { return false }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openCameraSettings() {
        openSettings("Privacy_Camera")
    }

    static func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    private static func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
