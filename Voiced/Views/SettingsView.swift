import SwiftUI
import VoicedKit

/// Settings, built the way a macOS Settings pane is: a grouped form of standard controls, with
/// the system drawing the rows and the glass. Black and white comes from the canvas behind the
/// form and from buttons that carry no accent colour.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    /// Lets previews and screenshots show the key rows mid-flow.
    var keyEditor = APIKeyEditor(arrangement: .formRows)
    /// Lets previews and screenshots show the window as it is on a smaller display: the height
    /// between that display's menu bar and Dock. `nil` follows the screen the window is on.
    var visibleScreenHeight: CGFloat?

    /// How tall the content may be before it has to scroll.
    @State private var heightLimit: CGFloat?

    private var hiddenIconAdvice: String {
        if model.menuBarItemMove == .stayedHidden {
            return "The icon is at the right end of the menu bar and still cannot be seen. In your menu bar manager's settings, such as Bartender's, move Voiced to Shown; a click on the manager's own icon may not reveal it."
        }
        return "A menu bar manager such as Bartender, or a full menu bar, is hiding the icon. This moves it to the right end of the menu bar, next to the system's icons."
    }

    /// The form at its natural height when the screen has room for it, which is how a Settings
    /// window looks; scrolling inside whatever height the screen does have when it has not.
    var body: some View {
        let limit = heightLimit ?? WindowHeightLimit.initial(visibleScreenHeight: visibleScreenHeight)
        ScrollView(.vertical) {
            form
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                // The form is as tall as its rows; the scrolling is done around it.
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 520)
        .frame(maxHeight: limit)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowHeightLimit(visibleScreenHeight: visibleScreenHeight, limit: Binding(get: { limit }, set: { heightLimit = $0 })))
        .background(Canvas())
        .containerBackground(Monochrome.canvas, for: .window)
        // No separate title bar strip: the canvas runs to the top edge.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // Carets, selections and spinners take the ink colour instead of the system accent.
        .tint(Monochrome.ink)
        .onDisappear {
            // The pill is only up for placing while this window is there to end it.
            model.pill.isPlacing = false
        }
    }

    private var form: some View {
        Form {
            Section("Hotkey") {
                LabeledContent {
                    HotkeyRecorder()
                } label: {
                    Text("Hold to Dictate")
                    Text("Hold it while you speak, release to insert.")
                }
                if model.hotkey.modifierKey == .function {
                    Text("To keep macOS from reacting to Fn, set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if model.hotkey != .default {
                    LabeledContent("Default") {
                        Button("Reset to \(Hotkey.default.displayName)") {
                            model.setHotkey(.default)
                        }
                    }
                }
            }

            Section {
                keyEditor
            } header: {
                Text("Grok API Key")
            } footer: {
                Text("Used to transcribe and tidy your dictation. Stored only in your Keychain.")
            }

            Section("Permissions") {
                PermissionFormRows(permissions: model.permissions)
            }

            Section("Pill") {
                PillPlacementPicker(pill: model.pill) {
                    Text("Placement")
                    Text("Next to Text puts the pill by the text cursor when you start dictating. An app that does not say where its cursor is gets the pill at the bottom of its window.")
                }
                LabeledContent {
                    Button("Reset Position") {
                        model.pill.reset()
                    }
                    .disabled(model.pill.placement == nil)
                    Button(model.pill.isPlacing ? "Done" : "Show Pill") {
                        model.pill.isPlacing.toggle()
                    }
                } label: {
                    Text("Fixed Place")
                    Text(model.pill.placement == nil
                        ? "Bottom center. Show the pill and drag it anywhere, now or while you dictate; it stays where you leave it."
                        : "Where you left it. Show the pill and drag it anywhere, now or while you dictate; it stays where you leave it.")
                }
            }

            Section("Cleanup") {
                CleanupToggle(cleanup: model.cleanup) {
                    Text("Clean Up Transcript")
                    Text("Fixes punctuation, capitalization and paragraphs, and removes filler words. When off, your words are inserted as they were transcribed.")
                }
            }

            Section("Menu Bar Icon") {
                LabeledContent("Status") {
                    StatusMark(isDone: !model.menuBarItemIsHidden, label: model.menuBarItemIsHidden ? "Hidden" : "Visible")
                }
                if model.menuBarItemIsHidden {
                    LabeledContent {
                        Button("Show in Menu Bar") {
                            model.bringMenuBarItemIntoView()
                        }
                        .disabled(model.menuBarItemMove == .moving)
                    } label: {
                        Text(model.menuBarItemMove == .stayedHidden ? "Still Hidden" : "Move into View")
                        Text(hiddenIconAdvice)
                    }
                    Label("You never need the icon to get here: open Voiced again while it is running.", systemImage: "arrow.up.forward.app")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel(permissions: Permissions(microphone: .granted, accessibility: false)))
}
