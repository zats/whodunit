import Foundation

#if os(macOS)

public enum AppMatchRule: Sendable, Hashable {
    case any
    case bundleID(String)
    case bundleIDPrefix(String)
    case bundleIDRegex(String)

    func matches(bundleID: String) -> Bool {
        switch self {
        case .any:
            return true
        case .bundleID(let exact):
            return bundleID == exact
        case .bundleIDPrefix(let prefix):
            return bundleID.hasPrefix(prefix)
        case .bundleIDRegex(let pattern):
            return (try? NSRegularExpression(pattern: pattern))
                .map { regex in
                    let range = NSRange(bundleID.startIndex..<bundleID.endIndex, in: bundleID)
                    return regex.firstMatch(in: bundleID, range: range) != nil
                } ?? false
        }
    }

    var specificity: Int {
        switch self {
        case .any: return 0
        case .bundleID: return 3
        case .bundleIDPrefix: return 2
        case .bundleIDRegex: return 1
        }
    }
}

public struct HeuristicRegistry: Sendable {
    struct Entry: Sendable {
        let name: String
        let match: AppMatchRule
        let priority: Int
        let run: @Sendable (_ app: AppDescriptor, _ target: URL) -> HeuristicResult?
    }

    public struct HeuristicResult: Sendable {
        public let displaysFile: Bool?
        public let visibleFile: Bool?
        public let hasTabs: Bool?
        public let debug: [String]

        public init(displaysFile: Bool?, visibleFile: Bool?, hasTabs: Bool? = nil, debug: [String] = []) {
            self.displaysFile = displaysFile
            self.visibleFile = visibleFile
            self.hasTabs = hasTabs
            self.debug = debug
        }
    }

    private var entries: [Entry]

    public init() {
        self.entries = []
    }

    public static var `default`: HeuristicRegistry {
        var reg = HeuristicRegistry()
        reg.entries =
            [GhosttyHeuristic.entry()]
            + VSCodeHeuristic.entries()
            + [StandardMacOSTabHeuristic.entry()]
        return reg
    }

    public mutating func register(
        name: String,
        match: AppMatchRule,
        priority: Int = 0,
        run: @escaping @Sendable (_ app: AppDescriptor, _ target: URL) -> HeuristicResult?
    ) {
        entries.append(Entry(name: name, match: match, priority: priority, run: run))
    }

    func applicable(to app: AppDescriptor) -> [Entry] {
        entries
            .filter { $0.match.matches(bundleID: app.bundleID) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.match.specificity != rhs.match.specificity { return lhs.match.specificity > rhs.match.specificity }
                return lhs.name < rhs.name
            }
    }
}

#endif
