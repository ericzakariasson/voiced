import CoreAudio
import Foundation
import Synchronization

/// The default input device as the system describes it. Reading it opens nothing: these are
/// property reads, the kind a sound settings window makes.
public struct InputDeviceStatus: Equatable, Sendable {
    public enum Transport: Equatable, Sendable {
        case builtIn
        case usb
        case thunderbolt
        case displayPort
        case hdmi
        case pci
        case fireWire
        case bluetooth
        /// A device made by software, which can stand in front of any other.
        case virtual
        /// Several devices presented as one.
        case aggregate
        /// Anything else, by the system's four-character code.
        case other(UInt32)

        /// Whether Voiced may find an input of this kind ahead of a hold.
        ///
        /// Opening a Bluetooth headset's input can move it to its call profile, which degrades
        /// whatever is playing. Whether finding the input does that without starting it has not
        /// been measured, so a Bluetooth input is left alone until the hotkey goes down. So is
        /// anything that may have one behind it, and anything unknown. Hardware on a wire has no
        /// such profile to change.
        public var canBeFoundAhead: Bool {
            switch self {
            case .builtIn, .usb, .thunderbolt, .displayPort, .hdmi, .pci, .fireWire: true
            case .bluetooth, .virtual, .aggregate, .other: false
            }
        }
    }

    /// The system's number for the device. It changes when the device is unplugged and plugged in again.
    public var id: UInt32
    /// Some process has the device running: recording from it or, for a device that also plays,
    /// playing through it. A microphone that is not running anywhere is not being listened to, by
    /// Voiced or anything else, so the orange dot is not lit on its account.
    public var isRunningSomewhere: Bool
    /// What the system reports as this process having the device running. Not to be relied on:
    /// on a Mac where it was read while Voiced itself was recording through `AVAudioEngine`, it
    /// was 0 every time, with `isRunningSomewhere` at 1. Kept for the log.
    public var isRunningHere: Bool
    public var transport: Transport
    public var sampleRate: Int

    public init(id: UInt32, isRunningSomewhere: Bool, isRunningHere: Bool, transport: Transport, sampleRate: Int) {
        self.id = id
        self.isRunningSomewhere = isRunningSomewhere
        self.isRunningHere = isRunningHere
        self.transport = transport
        self.sampleRate = sampleRate
    }

    /// The default input device now; `nil` when the Mac has none.
    public static func current() -> InputDeviceStatus? {
        guard
            let id: AudioDeviceID = read(kAudioHardwarePropertyDefaultInputDevice, of: AudioObjectID(kAudioObjectSystemObject)),
            id != kAudioObjectUnknown
        else {
            return nil
        }
        let runningSomewhere: UInt32 = read(kAudioDevicePropertyDeviceIsRunningSomewhere, of: id) ?? 0
        let runningHere: UInt32 = read(kAudioDevicePropertyDeviceIsRunning, of: id) ?? 0
        let transport: UInt32 = read(kAudioDevicePropertyTransportType, of: id) ?? 0
        let sampleRate: Float64 = read(kAudioDevicePropertyNominalSampleRate, of: id) ?? 0
        return InputDeviceStatus(
            id: id,
            isRunningSomewhere: runningSomewhere != 0,
            isRunningHere: runningHere != 0,
            transport: Transport(code: transport),
            sampleRate: Int(sampleRate)
        )
    }

    /// Numbers and states only: no device name, which can carry a person's name.
    public var logDescription: String {
        "id=\(id) transport=\(transport.logDescription) sampleRate=\(sampleRate) running here=\(isRunningHere ? 1 : 0) somewhere=\(isRunningSomewhere ? 1 : 0)"
    }

    private static func read<Value>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Value? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Value>.size)
        return withUnsafeTemporaryAllocation(of: Value.self, capacity: 1) { buffer in
            guard let pointer = buffer.baseAddress else { return nil }
            guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr, size == UInt32(MemoryLayout<Value>.size) else {
                return nil
            }
            return pointer.pointee
        }
    }
}

extension InputDeviceStatus.Transport {
    init(code: UInt32) {
        switch code {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypePCI: self = .pci
        case kAudioDeviceTransportTypeFireWire: self = .fireWire
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate: self = .aggregate
        default: self = .other(code)
        }
    }

    public var logDescription: String {
        switch self {
        case .builtIn: "builtIn"
        case .usb: "usb"
        case .thunderbolt: "thunderbolt"
        case .displayPort: "displayPort"
        case .hdmi: "hdmi"
        case .pci: "pci"
        case .fireWire: "fireWire"
        case .bluetooth: "bluetooth"
        case .virtual: "virtual"
        case .aggregate: "aggregate"
        case let .other(code): "other(\(code))"
        }
    }
}

/// Watches the default input device from a thread of its own and counts how often it was found
/// running, to show that something done meanwhile did not start it.
public final class InputDeviceWatch: Sendable {
    public struct Tally: Equatable, Sendable {
        public var samples = 0
        public var runningHere = 0
        public var runningSomewhere = 0
    }

    private final class State: Sendable {
        let tally = Mutex(Tally())
        let isStopped = Atomic<Bool>(false)
    }

    private let state = State()

    public init(
        every interval: Duration = .milliseconds(2),
        status: @escaping @Sendable () -> InputDeviceStatus? = InputDeviceStatus.current
    ) {
        let state = state
        let pause = Double(interval / .microseconds(1)) / 1_000_000
        Thread.detachNewThread {
            while !state.isStopped.load(ordering: .relaxed) {
                let device = status()
                let here = device?.isRunningHere == true ? 1 : 0
                let somewhere = device?.isRunningSomewhere == true ? 1 : 0
                state.tally.withLock { tally in
                    tally.samples += 1
                    tally.runningHere += here
                    tally.runningSomewhere += somewhere
                }
                Thread.sleep(forTimeInterval: pause)
            }
        }
    }

    /// What has been seen so far.
    public var tally: Tally {
        state.tally.withLock { $0 }
    }

    public func stop() -> Tally {
        state.isStopped.store(true, ordering: .relaxed)
        return tally
    }
}
