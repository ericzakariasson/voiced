#if DEBUG
import AppKit
import VoicedKit

/// `Voiced -VoicedMicrophoneCheck`, started by `make microphone-check`: measures that getting
/// the microphone ready ahead of a hold does not start it.
///
/// It does what Voiced does at launch and after the Mac wakes or is unlocked, three times, while
/// a second thread reads every two milliseconds whether the default input device is running: in
/// this process, and in any process, which is what the orange dot follows.
///
/// The copy never becomes an app. `VoicedMain` hands over to `runAndExit()` before SwiftUI and
/// AppKit are started, so there is no menu bar item, no window, no hotkey, no model and no
/// Keychain read, and nothing is written to Voiced's saved settings, which this copy shares
/// with the person's own Voiced. It can therefore run beside a running Voiced, which it never
/// quits, replaces or brings forward. Before it exits it says whether it stayed that way.
///
/// It touches audio only if macOS looks the Microphone grant up for Voiced and finds it granted.
/// Started from a shell, the grant macOS looks up is the one of the app that owns the shell, so
/// the Makefile starts this copy with `open`; started any other way it says so and checks nothing.
///
/// It cannot be left behind. A time limit is armed before anything else, on a thread that waits
/// on no queue: finding the input can take seconds, and a call into the audio system that never
/// came back would otherwise leave this copy on someone's Mac. Every line is written the moment
/// it is said, and each step is announced before it starts, so the file shows how far a copy
/// got even if it was ended from outside.
///
/// The last line it writes is `Microphone check exit code: N`, which the Makefile reads, since
/// `open` does not pass on an app's own exit code:
/// 0, the input device never ran anywhere; 1, this process had it running, or made a window;
/// 2, nothing could be checked; 3, the device ran during the check, started by this copy or by
/// another app, which cannot be told apart here; 5, the check did not finish within the time
/// limit and the copy ended itself.
///
/// `-VoicedMicrophoneCheckStandIn stuck`, `stuck-main` or `bluetooth` puts stand-ins in place of
/// the grant, the input device and the lookup, to try what the check does when a lookup never
/// returns or the input is of a kind Voiced leaves alone. A stand-in run touches no audio and
/// cannot pass.
enum DebugMicrophoneCheck {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-VoicedMicrophoneCheck")
    }

    /// A usual check takes two to five seconds: three lookups, the first of which may be the
    /// slow one, and a second of watching.
    private static let timeLimit: Duration = .seconds(20)

    /// Runs the check on the main queue, which `dispatchMain()` serves in place of an app's
    /// run loop, and ends the process.
    static func runAndExit() -> Never {
        StandaloneCheck.endProcess(after: timeLimit, code: timedOut, saying: [
            "Microphone check: no result within \(Int(timeLimit / .seconds(1))) s, so this copy is ending itself. The last line above is the step it did not get past.",
            "Microphone check exit code: \(timedOut)",
        ])
        say("Microphone check started as process \(getpid()). It ends itself after \(Int(timeLimit / .seconds(1))) s at the latest.")
        Task {
            var code = await check()
            if !leftNoTrace() {
                code = failed
            }
            say("Microphone check exit code: \(code)")
            // Not `exit`: everything is written already, and nothing an audio thread still holds
            // may delay the end.
            _exit(code)
        }
        dispatchMain()
    }

    private static func say(_ line: String) {
        StandaloneCheck.say(line)
    }

    /// What the check asks the Mac. The real answers, or stand-ins for trying the check itself.
    private struct Surroundings {
        var authorization: () -> MicrophoneAuthorization
        var inputDevice: @Sendable () -> InputDeviceStatus?
        var findInput: () async -> MicrophonePreparation
        var isStandIn = false

        static var real: Surroundings {
            let capture = MicrophoneCapture(sampleRate: Double(XAIConfiguration.default.sampleRate))
            return Surroundings(
                authorization: MicrophoneAuthorization.current,
                inputDevice: InputDeviceStatus.current,
                findInput: { await capture.prepare(after: .check) }
            )
        }

        /// Nothing here asks the audio system anything.
        ///
        /// - `stuck`: a lookup that never comes back, on a queue of its own as the real one is.
        /// - `stuck-main`: the same, but holding up the main queue as well.
        /// - `bluetooth`: an input of a kind Voiced leaves alone.
        static func standIn(_ name: String) -> Surroundings? {
            let transport: InputDeviceStatus.Transport
            switch name {
            case "stuck", "stuck-main": transport = .builtIn
            case "bluetooth": transport = .bluetooth
            default: return nil
            }
            let device = InputDeviceStatus(id: 0, isRunningSomewhere: false, isRunningHere: false, transport: transport, sampleRate: 48_000)
            let found = MicrophonePreparation(outcome: .found, duration: .zero, before: device, after: device)
            return Surroundings(
                authorization: { .granted },
                inputDevice: { device },
                findInput: {
                    if name == "stuck-main" {
                        waitForever()
                        return found
                    }
                    return await withCheckedContinuation { (continuation: CheckedContinuation<MicrophonePreparation, Never>) in
                        DispatchQueue(label: "com.ericzakariasson.Voiced.check-stand-in").async {
                            waitForever()
                            continuation.resume(returning: found)
                        }
                    }
                },
                isStandIn: true
            )
        }
    }

    /// Holds its thread for good: it waits for a signal nobody sends.
    private nonisolated static func waitForever() {
        DispatchSemaphore(value: 0).wait()
    }

    private static var requestedStandIn: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-VoicedMicrophoneCheckStandIn") else { return nil }
        return arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
    }

    /// Whether this copy stayed what it set out to be: a process that is no app and has no window.
    ///
    /// The window count alone would not show a menu bar icon: on macOS 26 an icon's window in
    /// the window list belongs to Control Center, not to the app. What rules an icon out is that
    /// there is no application object, which `MenuBarExtra` and every other window need.
    private static func leftNoTrace() -> Bool {
        let own = getpid()
        let everyWindow = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let owned = everyWindow.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == own }.count
        let isAnApp = NSApp != nil
        say("This copy, process \(own): \(isAnApp ? "became an app" : "never became an app, which a menu bar icon and a window need"); windows it owns: \(owned).")
        guard owned == 0, !isAnApp else {
            say("Microphone check failed: this copy was to make no app and no window.")
            return false
        }
        return true
    }

    private static let passed: Int32 = 0
    private static let failed: Int32 = 1
    private static let couldNotCheck: Int32 = 2
    private static let notSeenIdle: Int32 = 3
    private static let timedOut: Int32 = 5

    private static func check() async -> Int32 {
        var surroundings = Surroundings.real
        if let name = requestedStandIn {
            guard let standIn = Surroundings.standIn(name) else {
                say("Microphone check: there is no stand-in called \"\(name)\". Nothing was checked and no audio was touched.")
                return couldNotCheck
            }
            say("STAND-IN \"\(name)\": the grant, the input device and the lookup are stand-ins. No audio is touched, and this run says nothing about the microphone.")
            surroundings = standIn
        }

        // Before anything about audio: whose grant is this, and is it granted?
        let own = getpid()
        guard let responsible = responsibleProcess(for: own) else {
            say("Microphone check: could not tell which process macOS holds responsible for this one, so not whose Microphone grant applies. Nothing was checked and no audio was touched.")
            return couldNotCheck
        }
        guard responsible == own else {
            say("Microphone check: macOS holds process \(responsible) (\(name(of: responsible))) responsible for this copy, so it would look the Microphone grant up for that app and not for Voiced. Run `make microphone-check`, which starts the copy with `open`. Nothing was checked and no audio was touched.")
            return couldNotCheck
        }
        say("Responsible process: this copy of Voiced, so the Microphone grant looked up is Voiced's.")
        let authorization = surroundings.authorization()
        guard authorization == .granted else {
            say("Microphone check: the Microphone is \(authorization.logDescription) for this build, so Voiced would not prepare. Nothing was checked and no audio was touched. Grant it in Voiced's setup window, then run this again.")
            return couldNotCheck
        }

        say(surroundings.isStandIn
            ? "Stand-in: the Microphone is taken as granted, and the input device is the made-up one described next."
            : "The Microphone is granted to this build. Reading the input device's state, which opens nothing.")
        guard let before = surroundings.inputDevice() else {
            say("Microphone check: this Mac has no input device. Nothing was checked.")
            return couldNotCheck
        }
        // Before the device is described: of an input that is left alone, only its kind is told.
        guard before.transport.canBeFoundAhead else {
            return leftAlone(before.transport)
        }
        say("Input device before: \(before.logDescription)")
        guard !before.isRunningHere else {
            say("Microphone check failed: this process already has the input device running.")
            return failed
        }
        guard !before.isRunningSomewhere else {
            say("Microphone check: another app is using the microphone now, a call for example. Voiced leaves the input alone while that lasts, and so does this check. Nothing was checked. Run it again when the microphone is free.")
            return couldNotCheck
        }

        let watch = InputDeviceWatch(status: surroundings.inputDevice)
        let began = ContinuousClock.now
        var preparations: [MicrophonePreparation] = []
        for round in 1...3 {
            say("Preparation \(round) of 3: finding the input…")
            let preparation = await surroundings.findInput()
            if case let .skipped(.inputKind(transport)) = preparation.outcome {
                // The default input changed under the check.
                return leftAlone(transport)
            }
            say("Preparation \(round): \(preparation.logDescription)")
            preparations.append(preparation)
        }
        // A device that was going to start would have done so by now.
        say("Watching for one more second whether the device starts…")
        try? await Task.sleep(for: .seconds(1))
        let seen = watch.stop()
        let after = surroundings.inputDevice()
        say("Input device after: \(after?.logDescription ?? "none")")
        say("Watched it \(seen.samples) times in \(VoicedLog.milliseconds(since: began)) ms: running in this process \(seen.runningHere) times, in any process \(seen.runningSomewhere) times.")

        guard seen.runningHere == 0, after?.isRunningHere != true else {
            say("Microphone check failed: getting ready had the input device running in this process.")
            return failed
        }
        guard preparations.allSatisfy({ $0.outcome == .found }) else {
            say("Microphone check: a preparation did not find the input, because it was skipped or refused, so there is nothing to conclude. Run it again.")
            return couldNotCheck
        }
        guard seen.runningSomewhere == 0, after?.isRunningSomewhere != true, !preparations.contains(where: \.startedInput) else {
            // "In this process 0 times" proves nothing: a process does not reliably see its own recording there.
            say("Microphone check, not shown: the input device ran during the check, and from here it cannot be told whether this copy or another app started it. Run this again when nothing else is using the microphone. If the device runs again, it is this copy.")
            return notSeenIdle
        }
        guard !surroundings.isStandIn else {
            say("Microphone check: a stand-in run shows nothing about the microphone.")
            return couldNotCheck
        }
        say("Microphone check passed: the input was found \(preparations.count) times and the input device never ran, in this process or any other.")
        return passed
    }

    /// No lookup ran, so there is nothing to pass. Says the input's kind and nothing else of it.
    private static func leftAlone(_ transport: InputDeviceStatus.Transport) -> Int32 {
        say("Microphone check: the input is a \(transport.logDescription) one, which Voiced does not look ahead for, so no lookup ran and nothing was checked. Choose a built-in or wired input and run this again.")
        return couldNotCheck
    }

    private typealias ResponsibleProcessFunction = @convention(c) (pid_t) -> pid_t

    /// The process macOS attributes this one's privacy requests to. An app started by
    /// LaunchServices answers for itself; a binary run from a shell is answered for by the app
    /// that owns the shell. The function is not in the SDK's headers, hence the lookup by name.
    private static func responsibleProcess(for pid: pid_t) -> pid_t? {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else { return nil }
        let responsible = unsafeBitCast(symbol, to: ResponsibleProcessFunction.self)(pid)
        return responsible > 0 ? responsible : nil
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "name unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
#endif
