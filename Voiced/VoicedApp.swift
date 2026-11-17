import AppKit
import SwiftUI
import VoicedKit

/// Where the process starts: the app, except in the one mode that must not become one.
@main
enum VoicedMain {
    static func main() {
        #if DEBUG
        // The microphone check runs beside the person's own Voiced and shares its saved settings.
        // It ends here, before there is an app: no menu bar item, no window, no hotkey, no model,
        // and nothing for AppKit to save about a second icon.
        if DebugMicrophoneCheck.isRequested { DebugMicrophoneCheck.runAndExit() }
        // The other Debug runs do become an app, and must not be able to stay one for good.
        DebugRun.armTimeLimitIfRequested()
        #endif
        VoicedApp.main()
    }
}

struct VoicedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    init() {
        // Before the scenes, so before the menu bar item is created.
        #if DEBUG
        if DebugProbe.isRequested || DebugSnapshots.isRequested || DebugChecks.menuBarCheckIsRequested || DebugPillCaptures.isRequested { return }
        #endif
        MenuBarItem.prepareForLaunch()
    }

    var body: some Scene {
        // `isInserted` is what lets Voiced take the icon out and put it back at a new place.
        MenuBarExtra(isInserted: Binding(get: { model.menuBarItemIsInserted }, set: { model.menuBarItemIsInserted = $0 })) {
            MenuContentView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Voiced", id: WindowID.onboarding) {
            OnboardingView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(model.needsSetup ? .presented : .suppressed)

        Window("Voiced Settings", id: WindowID.settings) {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// The menu bar icon. It also hands the model SwiftUI's window opener, since the icon is the one
/// view that exists for the whole life of the app.
private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("Voiced")
            .onAppear {
                model.openWindow = { openWindow(id: $0) }
            }
    }

    private var symbol: String {
        if model.controller.isListening {
            return "waveform.circle.fill"
        }
        return model.needsSetup ? "waveform.badge.exclamationmark" : "waveform"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    let model = DebugRun.makeModelIfRequested() ?? AppModel()
    #else
    let model = AppModel()
    #endif
    private var indicator: IndicatorPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugProbe.isRequested {
            DebugProbe.run(model: model)
            return
        }
        if DebugPillCaptures.isRequested {
            DebugPillCaptures.run(model: model)
            return
        }
        #endif
        indicator = IndicatorPanel(controller: model.controller, pill: model.pill)
        model.start()
        if model.needsSetup {
            // The scene opens the setup window by itself; this puts it in front of every other app.
            model.windows.bringForward(.onboarding)
        }
        Task {
            // The menu bar item is created a moment after launch.
            try? await Task.sleep(for: .seconds(1))
            model.windows.logMenuBarItem()
        }
        #if DEBUG
        DebugSnapshots.runIfRequested(model: model)
        DebugChecks.runMenuBarCheckIfRequested(model: model)
        #endif
    }

    /// The app was opened again while it was running: from Finder, Spotlight, the Dock or `open`.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        model.showMainWindow()
        return false
    }
}
