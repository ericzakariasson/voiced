import SwiftUI
import VoicedKit

/// The choice between the pill's fixed place and next to the text: a standard segmented control,
/// the same one in the menu and in Settings, with both choices in view.
struct PillPlacementPicker<Label: View>: View {
    @Bindable var pill: PillSettings
    @ViewBuilder var label: Label

    var body: some View {
        Picker(selection: $pill.mode) {
            ForEach(PillPlacementMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            label
        }
        .pickerStyle(.segmented)
    }
}
