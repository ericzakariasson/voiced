#if DEBUG
import AppKit
import os
import VoicedKit

/// Settings for a Debug run: kept in memory, and gone with the process.
///
/// A copy started by `make snapshots`, `make pill-captures`, `make menu-bar-check` or
/// `make probe` has the bundle identifier of the person's own Voiced, so `UserDefaults.standard`
/// in it is that person's saved settings. A run that changed a setting there to try it, and was
/// ended before it could put the setting back, would leave it changed. So a run's settings are
/// one of these instead. It is a `UserDefaults` only because that is the type the app's settings
/// take; every way in and out is overridden below and keeps to the dictionary, and nothing here
/// calls the class it inherits from. Nothing is read from the Mac's preferences and nothing is
/// written to them, so nothing has to be put back and no settings domain is left behind.
nonisolated final class DebugSettings: UserDefaults {
    /// Never read and never written. A name of its own all the same, so that a way in that was
    /// missed below could not reach the person's settings: it would show as a file of this name.
    private static let unusedSuite = "com.ericzakariasson.Voiced.debug-run"

    private let values = OSAllocatedUnfairLock(uncheckedState: [String: Any]())

    init() {
        super.init(suiteName: Self.unusedSuite)!
    }

    // MARK: Reading

    override func object(forKey defaultName: String) -> Any? {
        values.withLockUnchecked { $0[defaultName] }
    }

    override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    override func array(forKey defaultName: String) -> [Any]? {
        object(forKey: defaultName) as? [Any]
    }

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }

    override func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    override func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }

    // Unlike the preferences, the four below read numbers only: a number or a truth value
    // saved as a string, which the preferences would convert, reads here as 0 or false.

    override func integer(forKey defaultName: String) -> Int {
        (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    override func float(forKey defaultName: String) -> Float {
        (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0
    }

    override func bool(forKey defaultName: String) -> Bool {
        (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    override func url(forKey defaultName: String) -> URL? {
        object(forKey: defaultName) as? URL
    }

    override func dictionaryRepresentation() -> [String: Any] {
        values.withLockUnchecked { $0 }
    }

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        dictionaryRepresentation()
    }

    // MARK: Writing

    override func set(_ value: Any?, forKey defaultName: String) {
        values.withLockUnchecked { $0[defaultName] = value }
    }

    // Numbers and truth values as the preferences give them back: as `NSNumber`.

    override func set(_ value: Int, forKey defaultName: String) {
        set(NSNumber(value: value) as Any?, forKey: defaultName)
    }

    override func set(_ value: Float, forKey defaultName: String) {
        set(NSNumber(value: value) as Any?, forKey: defaultName)
    }

    override func set(_ value: Double, forKey defaultName: String) {
        set(NSNumber(value: value) as Any?, forKey: defaultName)
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        set(NSNumber(value: value) as Any?, forKey: defaultName)
    }

    override func set(_ url: URL?, forKey defaultName: String) {
        set(url as Any?, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        values.withLockUnchecked { _ = $0.removeValue(forKey: defaultName) }
    }

    /// Unlike the preferences, which keep registered defaults apart from what is saved, this
    /// puts them among the saved values wherever nothing is saved yet. Removing a key therefore
    /// removes its registered default too, where the preferences would go back to showing it.
    override func register(defaults registrationDictionary: [String: Any]) {
        values.withLockUnchecked { $0.merge(registrationDictionary) { saved, _ in saved } }
    }

    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        values.withLockUnchecked { $0 = domain }
    }

    override func removePersistentDomain(forName domainName: String) {
        values.withLockUnchecked { $0.removeAll() }
    }

    override func synchronize() -> Bool {
        true
    }
}

/// What the Debug runs share: how a run is named on the command line, the settings of the app
/// it shows, and an end that does not depend on the run getting there.
enum DebugRun {
    /// The settings behind the run's own `AppModel`: what its menu bar panel and its Settings
    /// window change. They begin as on a first launch.
    static let settings = DebugSettings()

    /// What follows `flag` on the command line, such as the folder after `-VoicedSnapshots`.
    /// Read from the arguments themselves: asking `UserDefaults.standard` for it, which also
    /// holds them, would be asking the person's saved settings too.
    static func argument(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// The run this copy was started for, and how long it may take. A usual snapshot run takes
    /// three to four minutes, the pill captures four to six, the menu bar check half a minute
    /// and the probe two seconds.
    private static var requested: (name: String, limit: Duration)? {
        if DebugSnapshots.isRequested { return ("Snapshots", .seconds(15 * 60)) }
        if DebugPillCaptures.isRequested { return ("Pill captures", .seconds(30 * 60)) }
        if DebugChecks.menuBarCheckIsRequested { return ("Menu bar check", .seconds(3 * 60)) }
        if DebugProbe.isRequested { return ("Probe", .seconds(60)) }
        return nil
    }

    /// The exit code of a run that ended itself because it had not finished in time.
    static let timedOut: Int32 = 3

    /// Call before the app exists. A run puts windows in front of everything and clicks in its
    /// own windows; a click that is never answered, or anything else that never comes back,
    /// would otherwise leave this copy running on someone's Mac. The limit is kept on a thread
    /// that waits on no queue, so a main thread that is stuck cannot hold it up.
    static func armTimeLimitIfRequested() {
        guard let (name, limit) = requested else { return }
        // Each line into the file as it is printed, so that it shows how far a run got that
        // was ended, by the limit or from outside.
        setvbuf(stdout, nil, _IOLBF, 0)
        let minutes = Int(limit / .seconds(60))
        let lastLine = "\(name) failed: not finished after \(minutes) minutes, so this copy is ending itself. The last line above is how far it got."
        if DebugChecks.menuBarCheckIsRequested {
            // The one run that changes a saved setting, the menu bar icon's place: it puts
            // that back before it ends, by the limit or by a signal.
            DebugChecks.IconPlaceBeforeTheCheck.endTheCheck(after: limit, code: timedOut, saying: lastLine)
        } else {
            StandaloneCheck.endProcess(after: limit, code: timedOut, saying: [lastLine])
        }
    }

    /// The model of a Debug run, or `nil` when this copy is the app itself. Whichever run it
    /// is, its settings are its own: it never reads or changes the person's saved ones. The
    /// snapshots and the menu bar check show the app as it is on this Mac in everything else.
    static func makeModelIfRequested() -> AppModel? {
        if DebugProbe.isRequested { return DebugProbe.makeModel() }
        if DebugPillCaptures.isRequested { return DebugPillCaptures.makeModel() }
        if DebugSnapshots.isRequested || DebugChecks.menuBarCheckIsRequested { return AppModel(defaults: settings) }
        return nil
    }
}
#endif
