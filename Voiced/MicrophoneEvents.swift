import AppKit
import CoreAudio
import VoicedKit

/// Tells `MicrophoneReadiness` what happens to the Mac, so it can keep the microphone quick to
/// start without opening it outside a hold.
///
/// Finding the input device once took two seconds, on the first hold after the screen had been
/// locked, and those seconds came out of the first words of the dictation. So the input is found
/// ahead of time: when to, and when not to, is decided in `MicrophoneReadiness` and
/// `MicrophonePreparation`. This only listens: for sleep and wake, the lock and the unlock, and,
/// once the Microphone is granted, a change of default input device.
final class MicrophoneEvents {
    private let readiness: MicrophoneReadiness
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    init(sampleRate: Double) {
        let inputListener = DefaultInputListener()
        readiness = MicrophoneReadiness(
            prepare: { reason in
                await MicrophoneCapture(sampleRate: sampleRate).prepare(after: reason)
            },
            watchInputDevice: { onChange in
                inputListener.start(onChange)
            }
        )
    }

    /// Asks the system to say when the default input device changes. The system calls back on
    /// the main queue.
    private final class DefaultInputListener {
        private var onChange: (@MainActor () -> Void)?

        func start(_ onChange: @escaping @MainActor () -> Void) {
            self.onChange = onChange
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { @Sendable [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.onChange?()
                }
            }
        }
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, in: workspace, as: .systemWillSleep)
        observe(NSWorkspace.didWakeNotification, in: workspace, as: .systemDidWake)
        observe(NSWorkspace.screensDidSleepNotification, in: workspace, as: .displaysDidSleep)
        observe(NSWorkspace.screensDidWakeNotification, in: workspace, as: .displaysDidWake)
        let distributed = DistributedNotificationCenter.default()
        observe(Notification.Name("com.apple.screenIsLocked"), in: distributed, as: .screenLocked)
        observe(Notification.Name("com.apple.screenIsUnlocked"), in: distributed, as: .screenUnlocked)
        readiness.start()
    }

    func permissionsChanged() {
        readiness.permissionsChanged()
    }

    func holdBegan() {
        readiness.holdBegan()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter, as event: MicrophoneHistory.Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.readiness.record(event)
            }
        }
        observers.append((center, token))
    }
}
