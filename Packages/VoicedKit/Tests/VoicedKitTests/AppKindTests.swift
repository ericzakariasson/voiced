import Foundation
import Synchronization
import Testing
@testable import VoicedKit

/// A disk that answers from a script and writes down every path it was asked about.
private final class RecordingDisk: Sendable {
    private let touched = Mutex<[String]>([])
    private let symbolicLinks: Set<String>
    private let folders: [String: [String]]

    init(folders: [String: [String]] = [:], symbolicLinks: Set<String> = []) {
        self.folders = folders
        self.symbolicLinks = symbolicLinks
    }

    var paths: [String] {
        touched.withLock { $0 }
    }

    var disk: AppKind.Disk {
        AppKind.Disk(
            isSymbolicLink: { path in
                self.touched.withLock { $0.append(path) }
                return self.symbolicLinks.contains(path)
            },
            contentsOfDirectory: { path in
                self.touched.withLock { $0.append(path) }
                return self.folders[path]
            }
        )
    }
}

@Suite struct AppKindTests {
    private let home = "/Users/someone"

    private func kind(ofAppAt path: String, on recorder: RecordingDisk) -> AppKind {
        AppKind.of(bundle: URL(fileURLWithPath: path, isDirectory: true), homeDirectory: home, disk: recorder.disk)
    }

    @Test(arguments: [
        "/Applications/An Editor.app",
        "/Applications/Utilities/An Editor.app",
        "/System/Applications/An Editor.app",
        "/System/Library/CoreServices/An Editor.app",
        "/Users/someone/Applications/An Editor.app",
    ])
    func anAppInAStandardApplicationFolderIsLookedInto(path: String) {
        let recorder = RecordingDisk(folders: [path + "/Contents/Frameworks": ["Electron Framework.framework"]])

        #expect(kind(ofAppAt: path, on: recorder) == .electron)
        // Nothing outside that folder was touched.
        #expect(recorder.paths.allSatisfy { $0.hasPrefix(path) || path.hasPrefix($0 + "/") })
        #expect(recorder.paths.last == path + "/Contents/Frameworks")
    }

    @Test(arguments: [
        "/Users/someone/Desktop/An Editor.app",
        "/Users/someone/Documents/Tools/An Editor.app",
        "/Users/someone/Downloads/An Editor.app",
        "/Volumes/A Stick/An Editor.app",
        "/Volumes/server/Applications/An Editor.app",
        "/private/var/folders/xy/T/AppTranslocation/0000/d/An Editor.app",
        "/Users/someone/Library/Application Support/An Editor.app",
        "/Users/someone else/Applications/An Editor.app",
        "/ApplicationsElsewhere/An Editor.app",
        "/opt/An Editor.app",
    ])
    func anAppAnywhereElseIsNotTouchedOnDiskAtAll(path: String) {
        let recorder = RecordingDisk(folders: [path + "/Contents/Frameworks": ["Electron Framework.framework"]])

        #expect(kind(ofAppAt: path, on: recorder) == .unknown)
        #expect(recorder.paths.isEmpty)
    }

    @Test func aPathThatClimbsOutOfAStandardFolderIsNotTouched() {
        let recorder = RecordingDisk()

        #expect(kind(ofAppAt: "/Applications/../Users/someone/Downloads/An Editor.app", on: recorder) == .unknown)
        #expect(kind(ofAppAt: "/Applications/Utilities/../../Volumes/A Stick/An Editor.app", on: recorder) == .unknown)
        #expect(recorder.paths.isEmpty)
        // Worked out from the text of the path alone.
        #expect(AppKind.withoutDots("/Applications/./Utilities/../An Editor.app") == "/Applications/An Editor.app")
        #expect(AppKind.withoutDots("/../An Editor.app") == nil)
        #expect(AppKind.withoutDots("An Editor.app") == nil)
    }

    @Test(arguments: [
        "/Applications/An Editor.app",
        "/Applications/Linked Folder",
        "/Applications/Linked Folder/An Editor.app/Contents/Frameworks",
    ])
    func aSymbolicLinkOnTheWayIsNotFollowed(link: String) {
        let app = link.hasSuffix("Linked Folder") ? link + "/An Editor.app" : "/Applications/Linked Folder/An Editor.app"
        let path = link == "/Applications/An Editor.app" ? link : app
        let recorder = RecordingDisk(folders: [path + "/Contents/Frameworks": ["Electron Framework.framework"]], symbolicLinks: [link])

        #expect(kind(ofAppAt: path, on: recorder) == .unknown)
        // It stopped at the link: nothing at or beyond what the link points to was listed.
        #expect(recorder.paths.last == link)
        #expect(!recorder.paths.contains { $0.hasPrefix(link + "/") })
    }

    @Test func anAppWithNoBundleOrNoFrameworksFolder() {
        #expect(AppKind.of(bundle: nil, homeDirectory: home, disk: RecordingDisk().disk) == .unknown)
        #expect(AppKind.of(bundle: URL(string: "https://example.com/An%20Editor.app"), homeDirectory: home, disk: RecordingDisk().disk) == .unknown)
        // In a standard folder, with nothing to list: looked at, and not of the kinds that matter.
        #expect(kind(ofAppAt: "/Applications/A Plain App.app", on: RecordingDisk()) == .other)
    }

    @Test func theBundleIsLookedIntoOncePerRunOfAnApp() {
        var cache = AppKindCache()
        let run = AppKindCache.Run(pid: 501, launched: Date(timeIntervalSince1970: 1_000))

        // The first dictation into the app is told to look.
        #expect(cache.claim(run) == nil)
        // One that begins before the first has reported back does not look as well.
        #expect(cache.claim(run) == .unknown)
        cache.remember(.electron, for: run)
        #expect(cache.claim(run) == .electron)
        #expect(cache.claim(run) == .electron)

        // The same process number after the app was quit and opened again is a new run.
        #expect(cache.claim(AppKindCache.Run(pid: 501, launched: Date(timeIntervalSince1970: 2_000))) == nil)
    }
}
