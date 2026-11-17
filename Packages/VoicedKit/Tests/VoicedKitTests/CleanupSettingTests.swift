import Foundation
import Testing
@testable import VoicedKit

/// The setting against settings kept in memory, so a run leaves nothing behind on the Mac.
@MainActor
@Suite struct CleanupSettingTests {
    @Test func cleanupIsOnUntilSomebodySwitchesItOff() {
        let store = InMemorySettingsStore()

        let setting = CleanupSetting(defaults: store)

        #expect(setting.isOn)
        // Reading the setting is not choosing: nothing is saved for one who never touched it.
        #expect(store.values.isEmpty)
    }

    @Test func switchingCleanupOffIsRememberedByTheNextLaunch() {
        let store = InMemorySettingsStore()

        CleanupSetting(defaults: store).isOn = false

        // A setting made anew reads what the one before it saved, as after a relaunch.
        let relaunched = CleanupSetting(defaults: store)
        #expect(!relaunched.isOn)
        #expect(store.values[CleanupSetting.defaultsKey] as? Bool == false)
        #expect(store.values.count == 1)
    }

    @Test func switchingCleanupBackOnIsRememberedToo() {
        let store = InMemorySettingsStore()

        let setting = CleanupSetting(defaults: store)
        setting.isOn = false
        setting.isOn = true

        #expect(CleanupSetting(defaults: store).isOn)
        #expect(store.values[CleanupSetting.defaultsKey] as? Bool == true)
    }

    @Test func aSavedValueThatIsNeitherOnNorOffCountsAsNotChosen() {
        let store = InMemorySettingsStore([CleanupSetting.defaultsKey: "perhaps"])

        #expect(CleanupSetting(defaults: store).isOn)
    }
}
