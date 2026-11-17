import Foundation
import Observation
import os
import VoicedKit

/// Where the pill goes, by which rule, and whether it is being shown just so it can be placed.
@Observable
final class PillSettings {
    /// Where the user left the pill; `nil` until it has been moved, and after a reset.
    private(set) var placement: PillPlacement?
    /// The pill is on screen so it can be dragged into place, though nothing is being dictated.
    var isPlacing = false
    /// Whether the pill goes next to the text being edited or to its fixed place. Next to the
    /// text until somebody chooses; a choice is saved the moment it is made.
    var mode: PillPlacementMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
            VoicedLog.setup.notice("pill placement set to \(self.mode.rawValue, privacy: .public)")
        }
    }
    /// Where the text is, asked once per dictation while `mode` is next to text.
    @ObservationIgnored let textLookup = PillTextLookup()

    @ObservationIgnored private let defaults: UserDefaults
    private static let defaultsKey = "pillPlacement"
    private static let modeDefaultsKey = "pillPlacementMode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = PillPlacementMode(saved: defaults.string(forKey: Self.modeDefaultsKey))
        placement = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(PillPlacement.self, from: $0) }
    }

    func remember(_ placement: PillPlacement) {
        self.placement = placement
        if let data = try? JSONEncoder().encode(placement) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Back to the bottom centre of whichever screen the pointer is on.
    func reset() {
        placement = nil
        defaults.removeObject(forKey: Self.defaultsKey)
        VoicedLog.setup.notice("pill position reset to the default")
    }
}
