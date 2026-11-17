import CoreAudio
import Foundation
import Testing
@testable import VoicedKit

/// None of these reads a real device: the tests stay off the Mac's audio altogether.
@MainActor
@Suite struct InputDeviceStatusTests {
    @Test func aWatchCountsEveryTimeTheDeviceWasRunning() async throws {
        let running = InputDeviceStatus(id: 3, isRunningSomewhere: true, isRunningHere: true, transport: .usb, sampleRate: 44_100)

        let watch = InputDeviceWatch(every: .milliseconds(1), status: { running })
        try await waitUntil { watch.tally.samples >= 5 }
        let seen = watch.stop()

        #expect(seen.runningHere == seen.samples)
        #expect(seen.runningSomewhere == seen.samples)
    }

    @Test func theDeviceIsDescribedWithoutItsName() {
        let status = InputDeviceStatus(id: 91, isRunningSomewhere: true, isRunningHere: false, transport: .bluetooth, sampleRate: 24_000)

        #expect(status.logDescription == "id=91 transport=bluetooth sampleRate=24000 running here=0 somewhere=1")
    }

    @Test func onlyHardwareOnAWireIsFoundAheadOfAHold() {
        let foundAhead: [InputDeviceStatus.Transport] = [.builtIn, .usb, .thunderbolt, .displayPort, .hdmi, .pci, .fireWire]
        let leftAlone: [InputDeviceStatus.Transport] = [.bluetooth, .virtual, .aggregate, .other(0x61697270)]

        #expect(foundAhead.map(\.canBeFoundAhead) == Array(repeating: true, count: foundAhead.count))
        #expect(leftAlone.map(\.canBeFoundAhead) == Array(repeating: false, count: leftAlone.count))
        #expect(InputDeviceStatus.Transport(code: kAudioDeviceTransportTypeBluetoothLE).canBeFoundAhead == false)
    }

    @Test func transportsAreNamedByKind() {
        #expect(InputDeviceStatus.Transport(code: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(InputDeviceStatus.Transport(code: kAudioDeviceTransportTypeUSB) == .usb)
        #expect(InputDeviceStatus.Transport(code: kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
        #expect(InputDeviceStatus.Transport(code: 0x1234).logDescription == "other(4660)")
    }
}
