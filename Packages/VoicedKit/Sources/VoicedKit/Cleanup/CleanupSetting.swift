import Foundation
import Observation

/// Where a setting is kept between launches: the two things `UserDefaults` does that a setting
/// needs. The app's preferences are such a store as they stand. Tests keep theirs in memory, so
/// that a test run writes nothing into the settings of whoever runs it.
public protocol SettingsStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Bool, forKey defaultName: String)
}

extension UserDefaults: SettingsStore {}

/// Whether a dictation gets its cleanup pass. On until somebody switches it off; a choice is
/// saved the moment it is made.
@MainActor
@Observable
public final class CleanupSetting {
    /// Where the choice is kept in the preferences. Nothing there, or nothing that reads as on
    /// or off, means nobody has chosen.
    public static let defaultsKey = "cleanupIsOn"
    public static let whenNotChosen = true

    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            defaults.set(isOn, forKey: Self.defaultsKey)
            VoicedLog.setup.notice("cleanup switched \(self.isOn ? "on" : "off", privacy: .public)")
        }
    }

    @ObservationIgnored private let defaults: any SettingsStore

    public init(defaults: any SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        isOn = defaults.object(forKey: Self.defaultsKey) as? Bool ?? Self.whenNotChosen
    }
}
