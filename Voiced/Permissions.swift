import AppKit
import AVFoundation
import Observation

/// Tracks the two system permissions Voiced needs and asks for them.
@Observable
final class Permissions {
    enum MicrophoneStatus: Equatable {
        case notDetermined
        case granted
        case denied
    }

    private(set) var microphone: MicrophoneStatus
    /// Accessibility covers both watching for the hotkey and pasting into the focused app.
    private(set) var accessibility: Bool

    @ObservationIgnored var onChange: (() -> Void)?
    /// Called just before a system prompt is triggered, so Voiced can come to the front first.
    @ObservationIgnored var willPrompt: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let isFixed: Bool
    @ObservationIgnored private var hasShownAccessibilityPrompt = false

    var allGranted: Bool {
        microphone == .granted && accessibility
    }

    init() {
        isFixed = false
        microphone = Self.currentMicrophoneStatus()
        accessibility = AXIsProcessTrusted()
    }

    /// Fixed values for previews and screenshots; never touches the system.
    init(microphone: MicrophoneStatus, accessibility: Bool) {
        isFixed = true
        self.microphone = microphone
        self.accessibility = accessibility
    }

    /// The system sends no notification when Accessibility is toggled, so poll while it matters.
    func startMonitoring() {
        guard !isFixed, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isFixed else { return }
        let newMicrophone = Self.currentMicrophoneStatus()
        let newAccessibility = AXIsProcessTrusted()
        guard newMicrophone != microphone || newAccessibility != accessibility else { return }
        microphone = newMicrophone
        accessibility = newAccessibility
        onChange?()
    }

    func requestMicrophone() {
        guard !isFixed else { return }
        switch microphone {
        case .notDetermined:
            willPrompt?()
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refresh()
            }
        case .denied:
            openSettings(pane: "Privacy_Microphone")
        case .granted:
            break
        }
    }

    func requestAccessibility() {
        guard !isFixed, !accessibility else { return }
        guard hasShownAccessibilityPrompt else {
            // The system prompt adds Voiced to the Accessibility list and offers to open System Settings.
            // The key is `kAXTrustedCheckOptionPrompt`, spelled out because the constant is not concurrency-safe.
            hasShownAccessibilityPrompt = true
            willPrompt?()
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        // macOS shows that prompt once; after that, go to the list directly.
        openSettings(pane: "Privacy_Accessibility")
    }

    private func openSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func currentMicrophoneStatus() -> MicrophoneStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}
