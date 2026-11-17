#if DEBUG
import AppKit
import VoicedKit

/// `Voiced -VoicedProbe` starts a copy that touches nothing: no hotkey tap, no Keychain, no
/// permission checks, no window, and none of the saved settings but the menu bar icon's place,
/// which macOS reads for itself. It reports where its menu bar item ended up and whether SwiftUI's
/// window opener was installed, then quits.
///
/// For finding out why the menu bar icon cannot be seen on a Mac without disturbing a copy of
/// Voiced that is already running there.
enum DebugProbe {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoicedProbe")
    }

    private struct NoSecrets: SecretStore {
        func read() -> String? { "probe" }
        func save(_ secret: String) {}
        func delete() {}
    }

    /// A model that believes setup is complete, so no window opens and nothing is asked for.
    static func makeModel() -> AppModel {
        AppModel(permissions: Permissions(microphone: .granted, accessibility: true), secretStore: NoSecrets(), defaults: DebugRun.settings)
    }

    static func run(model: AppModel) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            model.windows.logMenuBarItem()
            let statusWindow = NSApp.windows.first { $0.className == "NSStatusBarWindow" }
            let placement = MenuBarItemPlacement.of(itemFrame: statusWindow?.frame, displayFrames: NSScreen.screens.map(\.frame))
            print("menu bar item: \(placement.logDescription)")
            if let statusWindow {
                print("status window: frame=\(statusWindow.frame) screen=\(statusWindow.screen?.localizedName ?? "none") visible=\(statusWindow.isVisible) occluded=\(!statusWindow.occlusionState.contains(.visible))")
            }
            print("window opener installed: \(model.openWindow != nil)")
            print("windows: \(NSApp.windows.map { "\($0.className) id=\($0.identifier?.rawValue ?? "-") visible=\($0.isVisible)" })")
            NSApp.terminate(nil)
        }
    }
}
#endif
