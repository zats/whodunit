import Foundation

#if os(macOS)
import AppKit
#endif

public enum FileVisibility: String, Codable, Sendable, Hashable {
    case tabHidden = "tab_hidden"
    case tabVisible = "tab_visible"
    case visible = "visible"
}

public struct AppUsage: Sendable, Hashable {
    public let bundleID: String
    public let pid: pid_t
    public let name: String

    public let isFrontmost: Bool
    public let hasTabs: Bool
    public let displaysFile: Bool
    public let isTabDisplayingFileVisible: Bool

    public let debug: [DetectionStep]?

    public var fileVisibility: FileVisibility {
        if isTabDisplayingFileVisible {
            return hasTabs ? .tabVisible : .visible
        }
        return .tabHidden
    }

    public init(
        bundleID: String,
        pid: pid_t,
        name: String,
        isFrontmost: Bool,
        hasTabs: Bool,
        displaysFile: Bool,
        isTabDisplayingFileVisible: Bool,
        debug: [DetectionStep]? = nil
    ) {
        self.bundleID = bundleID
        self.pid = pid
        self.name = name
        self.isFrontmost = isFrontmost
        self.hasTabs = hasTabs
        self.displaysFile = displaysFile
        self.isTabDisplayingFileVisible = isTabDisplayingFileVisible
        self.debug = debug
    }
}

public struct DetectionStep: Sendable, Hashable {
    public let name: String
    public let notes: [String]

    public init(name: String, notes: [String] = []) {
        self.name = name
        self.notes = notes
    }
}

public struct DetectionOptions: Sendable {
    public let includeDebug: Bool
    public let registry: HeuristicRegistry

    public init(includeDebug: Bool, registry: HeuristicRegistry) {
        self.includeDebug = includeDebug
        self.registry = registry
    }

    public static let `default` = DetectionOptions(includeDebug: false, registry: .default)
}
