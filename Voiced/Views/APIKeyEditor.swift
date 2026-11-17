import SwiftUI

/// Field and buttons for entering, replacing or removing the Grok API Key.
///
/// Standard controls in two arrangements: fixed heights for the setup window, where saving,
/// checking, accepting and rejecting a key must change what is written and never where anything
/// sits, and form rows for Settings.
struct APIKeyEditor: View {
    @Environment(AppModel.self) private var model

    enum Status: Equatable {
        case idle
        case checking
        case message(String, isError: Bool)
    }

    enum Arrangement {
        /// One block of fixed height, for the setup window.
        case fixed
        /// Rows of a grouped form, for Settings.
        case formRows
    }

    var arrangement = Arrangement.fixed

    @State private var input: String
    @State private var status: Status

    static let fixedHeight: CGFloat = Monochrome.controlHeight + spacing + statusHeight
    private static let spacing: CGFloat = 8
    /// Room for two lines, which the longest message needs.
    private static let statusHeight: CGFloat = 32

    /// The starting values exist so previews and screenshots can show the editor mid-flow.
    init(arrangement: Arrangement = .fixed, input: String = "", status: Status = .idle) {
        self.arrangement = arrangement
        _input = State(initialValue: input)
        _status = State(initialValue: status)
    }

    var body: some View {
        switch arrangement {
        case .fixed:
            VStack(alignment: .leading, spacing: Self.spacing) {
                HStack(spacing: 8) {
                    field
                    saveButton.buttonStyle(.ink)
                }
                .frame(height: Monochrome.controlHeight)

                HStack(alignment: .top, spacing: 8) {
                    statusLine
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    // Always laid out, so the status line keeps its width when a key appears.
                    removeButton
                        .controlSize(.small)
                        .opacity(model.hasAPIKey ? 1 : 0)
                        .accessibilityHidden(!model.hasAPIKey)
                }
                .frame(height: Self.statusHeight, alignment: .top)
            }
            .frame(height: Self.fixedHeight)

        case .formRows:
            LabeledContent("Key") {
                HStack(spacing: 8) {
                    field
                    saveButton
                }
            }
            LabeledContent("Status") {
                HStack(spacing: 10) {
                    statusLine
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    if model.hasAPIKey {
                        removeButton
                    }
                }
            }
        }
    }

    private var field: some View {
        SecureField("Grok API Key", text: $input, prompt: Text(model.hasAPIKey ? "Paste a New Key to Replace It" : "xai-…"))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .onSubmit(save)
            .disabled(status == .checking)
    }

    private var saveButton: some View {
        Button("Save", action: save)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .checking)
    }

    private var removeButton: some View {
        Button("Remove", action: remove)
            .disabled(!model.hasAPIKey || status == .checking)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking the Key…")
            }
            .foregroundStyle(.secondary)
        case let .message(text, isError):
            // A triangle for a problem, a tick for success: shape and wording, not red and green.
            Label(text, systemImage: isError ? "exclamationmark.triangle" : "checkmark")
                .foregroundStyle(.primary)
                .help(text)
        case .idle:
            if model.hasAPIKey {
                Label("Saved in Your Keychain", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Link(destination: URL(string: "https://console.x.ai")!) {
                    Text("Get a Grok API Key at console.x.ai").underline()
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard status != .checking else { return }
        let candidate = input
        status = .checking
        Task {
            switch await model.saveAPIKey(candidate) {
            case .saved:
                input = ""
                status = .message("The key works. Saved in your Keychain.", isError: false)
            case let .savedUnverified(reason):
                input = ""
                status = .message(reason, isError: true)
            case let .rejected(reason):
                status = .message(reason, isError: true)
            }
        }
    }

    private func remove() {
        if model.removeAPIKey() {
            input = ""
            status = .idle
        } else {
            status = .message("The Keychain would not remove the key.", isError: true)
        }
    }
}
