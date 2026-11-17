import SwiftUI

/// What the two permission rows say, shared by the setup window and Settings.
enum PermissionText {
    static let microphoneDetail = "Voiced listens only while you hold the hotkey."
    static let accessibilityDetail = "Lets Voiced notice the hotkey in any app and paste your words where you are typing."

    static func microphoneAction(_ status: Permissions.MicrophoneStatus) -> String {
        status == .denied ? "Open Settings" : "Allow"
    }
}

// MARK: - Setup window rows

struct MicrophonePermissionRow: View {
    var permissions: Permissions
    var number: String?

    var body: some View {
        SettingRow(number: number, title: "Microphone", detail: PermissionText.microphoneDetail) {
            PermissionControl(
                isGranted: permissions.microphone == .granted,
                actionTitle: PermissionText.microphoneAction(permissions.microphone),
                isMainAction: true
            ) {
                permissions.requestMicrophone()
            }
        }
    }
}

struct AccessibilityPermissionRow: View {
    var permissions: Permissions
    var number: String?

    var body: some View {
        SettingRow(number: number, title: "Accessibility", detail: PermissionText.accessibilityDetail) {
            PermissionControl(isGranted: permissions.accessibility, actionTitle: "Open Settings", isMainAction: true) {
                permissions.requestAccessibility()
            }
        }
    }
}

// MARK: - Settings rows

/// The same two permissions as rows of a grouped form.
struct PermissionFormRows: View {
    var permissions: Permissions

    var body: some View {
        LabeledContent {
            PermissionControl(
                isGranted: permissions.microphone == .granted,
                actionTitle: PermissionText.microphoneAction(permissions.microphone),
                isMainAction: false
            ) {
                permissions.requestMicrophone()
            }
        } label: {
            Text("Microphone")
            Text(PermissionText.microphoneDetail)
        }

        LabeledContent {
            PermissionControl(isGranted: permissions.accessibility, actionTitle: "Open Settings", isMainAction: false) {
                permissions.requestAccessibility()
            }
        } label: {
            Text("Accessibility")
            Text(PermissionText.accessibilityDetail)
        }
    }
}

/// The button that asks for a permission, replaced in place by "Allowed" once it is granted.
private struct PermissionControl: View {
    var isGranted: Bool
    var actionTitle: String
    /// In the setup window the button is the thing to do next; in Settings it is one control among several.
    var isMainAction: Bool
    var action: () -> Void

    var body: some View {
        if isGranted {
            StatusMark(isDone: true, label: "Allowed")
        } else if isMainAction {
            Button(actionTitle, action: action)
                .buttonStyle(.ink)
        } else {
            Button(actionTitle, action: action)
        }
    }
}
