import Foundation

/// What an app is built on, as far as it matters for finding its text: apps built on Electron
/// and browsers built on Chromium give no position for their text until something has switched
/// their accessibility on.
///
/// It is told from the names of the frameworks inside the app's bundle and goes into the log
/// as one word. The app's own name and identifier are never logged.
public enum AppKind: String, Sendable {
    case electron
    case chromium
    case other
    /// Not looked at: the app is not in one of the standard application folders.
    case unknown

    /// - Parameter frameworks: The names of the items in the app's `Contents/Frameworks`.
    public static func of(frameworks: [String]) -> AppKind {
        if frameworks.contains("Electron Framework.framework") {
            return .electron
        }
        let isChromium = frameworks.contains { name in
            name == "Chromium Embedded Framework.framework" || chromiumBrowsers.contains { name == "\($0) Framework.framework" }
        }
        return isChromium ? .chromium : .other
    }

    /// The two things this needs from the disk, so that tests can see what is touched.
    public struct Disk: Sendable {
        /// Whether the item at a path is a symbolic link. Must not follow the link.
        public var isSymbolicLink: @Sendable (String) -> Bool
        /// The names of the items in a folder; `nil` when it cannot be listed.
        public var contentsOfDirectory: @Sendable (String) -> [String]?

        public init(isSymbolicLink: @escaping @Sendable (String) -> Bool, contentsOfDirectory: @escaping @Sendable (String) -> [String]?) {
            self.isSymbolicLink = isSymbolicLink
            self.contentsOfDirectory = contentsOfDirectory
        }

        public static let real = Disk(
            isSymbolicLink: { path in
                (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
            },
            contentsOfDirectory: { path in
                try? FileManager.default.contentsOfDirectory(atPath: path)
            }
        )
    }

    /// The kind of the app at `bundle`.
    ///
    /// The disk is touched only for an app inside a standard application folder. Opening the
    /// bundle of an app that runs from Desktop, Documents or Downloads, or from a removable or
    /// network volume, can make macOS ask the person whether Voiced may access that place, and
    /// Voiced has no business raising that question. Such an app is `.unknown`, decided from
    /// its path alone. A symbolic link on the way counts as leaving the folder.
    public static func of(
        bundle: URL?,
        homeDirectory: String = NSHomeDirectory(),
        disk: Disk = .real
    ) -> AppKind {
        guard let bundle, bundle.isFileURL, let path = withoutDots(bundle.path),
              let root = standardFolders(homeDirectory: homeDirectory).first(where: { path.hasPrefix($0 + "/") }) else {
            return .unknown
        }
        // Every step from the standard folder down to the frameworks must be a real item there.
        var step = root
        let below = path.dropFirst(root.count).split(separator: "/").map(String.init) + ["Contents", "Frameworks"]
        for component in below {
            step += "/" + component
            if disk.isSymbolicLink(step) {
                return .unknown
            }
        }
        return of(frameworks: disk.contentsOfDirectory(step) ?? [])
    }

    /// An absolute path with its `.` and `..` worked out on paper. Foundation's own ways of
    /// tidying a path may consult the disk, which is the thing to avoid here.
    static func withoutDots(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var components: [Substring] = []
        for component in path.split(separator: "/") where component != "." {
            if component == ".." {
                guard !components.isEmpty else { return nil }
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    /// Where apps are installed. Reading inside these never needs the person's leave.
    static func standardFolders(homeDirectory: String) -> [String] {
        ["/Applications", "/System/Applications", "/System/Library/CoreServices", homeDirectory + "/Applications"]
    }

    /// Browsers that name their Chromium framework after themselves. One that is not listed
    /// counts as `.other`.
    private static let chromiumBrowsers = [
        "Google Chrome", "Chromium", "Microsoft Edge", "Brave Browser", "Vivaldi", "Opera", "Arc",
    ]
}

/// Remembers the kind of each running app, so that an app's bundle is looked into once for
/// each run of the app and not once per dictation.
public struct AppKindCache: Sendable {
    /// One run of an app: a process identifier can be given out again after the app quits.
    public struct Run: Hashable, Sendable {
        public var pid: Int32
        public var launched: Date?

        public init(pid: Int32, launched: Date?) {
            self.pid = pid
            self.launched = launched
        }
    }

    private var kinds: [Run: AppKind] = [:]
    /// More than anyone has open at once; past it the cache starts over.
    private static let limit = 64

    public init() {}

    /// The kind already found for this run of the app, or `nil` when the caller is the one to
    /// find it. Says `nil` once per run: until the caller has reported back with `remember`,
    /// later callers are told `.unknown` and do not look.
    public mutating func claim(_ run: Run) -> AppKind? {
        if let known = kinds[run] {
            return known
        }
        if kinds.count >= Self.limit {
            kinds.removeAll()
        }
        kinds[run] = .unknown
        return nil
    }

    public mutating func remember(_ kind: AppKind, for run: Run) {
        kinds[run] = kind
    }
}
