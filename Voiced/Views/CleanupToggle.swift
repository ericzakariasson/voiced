import SwiftUI
import VoicedKit

/// The switch for the cleanup pass: a standard one, the same in the menu and in Settings.
struct CleanupToggle<Label: View>: View {
    @Bindable var cleanup: CleanupSetting
    @ViewBuilder var label: Label

    var body: some View {
        Toggle(isOn: $cleanup.isOn) {
            label
        }
        .toggleStyle(.switch)
    }
}
