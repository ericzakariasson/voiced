import SwiftUI
import VoicedKit

/// The panel that opens from the menu bar icon: what Voiced is doing, and the way to its settings.
///
/// The hotkey, where the pill goes and whether dictations are cleaned up can be changed right
/// here, with the same controls Settings has. The key and the permissions are shown as they
/// stand, and their rows open the window that changes them.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.needsSetup {
                Button {
                    model.show(WindowID.onboarding)
                } label: {
                    Text("Finish Setup…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.ink)
                .controlSize(.large)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Hairline()

            row("Hotkey") {
                HotkeyRecorder()
            }
            Hairline()
            row("Pill") {
                PillPlacementPicker(pill: model.pill) {
                    Text("Pill")
                }
                .labelsHidden()
                .fixedSize()
            }
            Hairline()
            row("Cleanup") {
                CleanupToggle(cleanup: model.cleanup) {
                    Text("Cleanup")
                }
                .labelsHidden()
            }
            Hairline()
            linkRow("Grok API Key", value: model.hasAPIKey ? "Saved" : "Not Set", isDone: model.hasAPIKey) {
                model.show(WindowID.settings)
            }
            Hairline()
            linkRow("Permissions", value: model.permissions.allGranted ? "Allowed" : "Needed", isDone: model.permissions.allGranted) {
                model.show(model.permissions.allGranted ? WindowID.settings : WindowID.onboarding)
            }
            Hairline()

            if model.hotkeyIsUnavailable, !model.needsSetup {
                message("Quit and reopen Voiced so macOS lets it watch for the hotkey.", symbol: "exclamationmark.triangle")
            }
            if let notice = model.controller.notice {
                // An octagon for an error, a triangle for a warning.
                message(notice.message, symbol: notice.kind == .error ? "exclamationmark.octagon" : "exclamationmark.triangle")
            }

            HStack(spacing: 8) {
                Button("Settings…") {
                    model.show(WindowID.settings)
                }
                .keyboardShortcut(",")

                Spacer(minLength: 0)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(14)
        }
        .frame(width: 300)
        // Carets, selections and spinners take the ink colour instead of the system accent.
        .tint(Monochrome.ink)
    }

    private var header: some View {
        HStack(spacing: 10) {
            MarkBadge(size: 30)
            Text("Voiced")
                .font(.headline)
            Spacer(minLength: 8)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    /// A row that shows a setting's state and opens the window where it is changed.
    private func linkRow(_ title: String, value: String, isDone: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title) {
                StatusMark(isDone: isDone, label: value)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        Hairline()
    }

    private var statusText: String {
        switch model.controller.phase {
        case .recording:
            return model.controller.isListening ? "Listening" : "Starting Microphone"
        case .transcribing, .cleaning, .inserting:
            return model.controller.isPolishing ? "Polishing" : "Transcribing"
        case .idle, .starting:
            if !model.hasAPIKey { return "Needs a Grok API Key" }
            if !model.permissions.allGranted { return "Needs Permissions" }
            if model.hotkeyIsUnavailable { return "Hotkey Unavailable" }
            return "Ready"
        }
    }
}

#Preview {
    MenuContentView()
        .environment(AppModel(permissions: Permissions(microphone: .granted, accessibility: true)))
}
