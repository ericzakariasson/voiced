import SwiftUI
import VoicedKit

/// First-run setup: the two permissions and the Grok API Key, on one page.
///
/// The window has one size and every row has one height. As steps are completed, a button turns
/// into a status in the same slot and a line of text changes; nothing moves.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    /// Lets previews and screenshots show the key step mid-flow.
    var keyEditor = APIKeyEditor()

    private var stepsDone: Int {
        [model.permissions.microphone == .granted, model.permissions.accessibility, model.hasAPIKey]
            .filter { $0 }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Panel {
                MicrophonePermissionRow(permissions: model.permissions, number: "1")
                Hairline()
                AccessibilityPermissionRow(permissions: model.permissions, number: "2")
                Hairline()
                keyStep
            }

            MenuBarIconNote()

            footer
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8)
        .frame(width: 520)
        .background(Canvas())
        .containerBackground(Monochrome.canvas, for: .window)
        // Carets, selections and spinners take the ink colour instead of the system accent.
        .tint(Monochrome.ink)
    }

    private var header: some View {
        HStack(spacing: 16) {
            MarkBadge(size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Voiced")
                    .font(.system(size: 24, weight: .regular))
                    .tracking(-0.4)
                    .lineLimit(1)
                Text("Hold a key, speak, and your words appear where you are typing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 56)
    }

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(
                number: "3",
                title: "Grok API Key",
                detail: "Voiced uses your own Grok API Key. It is stored only in your Keychain."
            ) {
                StatusMark(isDone: model.hasAPIKey, label: model.hasAPIKey ? "Saved" : "Not Set")
            }
            keyEditor
                .padding(.leading, 52)
                .padding(.trailing, 18)
                .padding(.bottom, 16)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(stepsDone) of 3")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Group {
                if model.needsSetup {
                    Text("Finish the steps above to start dictating.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text("Hold")
                        Keycap(label: model.hotkey.displayName)
                        Text("and speak.")
                    }
                }
            }
            .font(.body)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(model.needsSetup ? "Later" : "Done") {
                dismissWindow(id: WindowID.onboarding)
                model.closeDirectWindow(.onboarding)
            }
            .buttonStyle(.ink)
            .keyboardShortcut(.defaultAction)
            .frame(width: 84, alignment: .trailing)
        }
        .frame(height: Monochrome.controlHeight)
    }
}

/// Where to find Voiced once setup is done, or what to do when its menu bar icon cannot be seen.
/// Two lines tall either way, so the window keeps its size when the answer changes.
struct MenuBarIconNote: View {
    @Environment(AppModel.self) private var model

    static let visibleText = "Voiced lives in the menu bar: click the waveform icon for the hotkey and Settings."
    static let hiddenText = "The menu bar icon is hidden. Opening Voiced again while it runs brings this window back."
    static let stayedHiddenText = "Still hidden. In your menu bar manager's settings, such as Bartender's, move Voiced to Shown."

    private var text: String {
        guard model.menuBarItemIsHidden else { return Self.visibleText }
        return model.menuBarItemMove == .stayedHidden ? Self.stayedHiddenText : Self.hiddenText
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label {
                Text(text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: model.menuBarItemIsHidden ? "exclamationmark.triangle" : "menubar.arrow.up.rectangle")
            }
            .font(.callout)
            .foregroundStyle(model.menuBarItemIsHidden ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.menuBarItemIsHidden {
                Button("Show in Menu Bar") {
                    model.bringMenuBarItemIntoView()
                }
                .disabled(model.menuBarItemMove == .moving)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel(permissions: Permissions(microphone: .notDetermined, accessibility: false)))
}
