import Foundation

#if os(macOS)
import ApplicationServices

enum GhosttyHeuristic {
    private static let bundleID = "com.mitchellh.ghostty"

    static func entry() -> HeuristicRegistry.Entry {
        HeuristicRegistry.Entry(
            name: "GhosttyHeuristic",
            match: .bundleID(bundleID),
            priority: 50,
            run: { app, target in
                evaluate(app: app, target: target)
            }
        )
    }

    static func evaluate(app: AppDescriptor, target: URL) -> HeuristicRegistry.HeuristicResult? {
        guard Accessibility.isTrusted() else {
            return HeuristicRegistry.HeuristicResult(
                displaysFile: nil,
                visibleFile: nil,
                hasTabs: nil,
                debug: ["AX not trusted"]
            )
        }

        let targetPath = PathNormalizer.normalizeFileURL(target).path

        let axApp = Accessibility.appElement(pid: app.pid)
        let rawWindows = Accessibility.attributeValue(axApp, kAXWindowsAttribute)
        let windows =
            (rawWindows as? [AXUIElement])
            ?? (rawWindows as? [AnyObject])?.map { $0 as! AXUIElement }
            ?? []

        var tabModels: [TabModel] = []
        tabModels.reserveCapacity(8)

        var hasTabs = false
        for w in windows {
            let tabs = extractTabs(from: w)
            if tabs.count > 1 { hasTabs = true }
            tabModels.append(contentsOf: tabs)
        }

        let descendantPIDs = ProcessInspector.descendantPIDs(of: app.pid)

        var matchingPIDs: [pid_t] = []
        matchingPIDs.reserveCapacity(4)
        for pid in descendantPIDs {
            if ProcessInspector.processHasOpenFile(pid: pid, path: targetPath) {
                matchingPIDs.append(pid)
            }
        }

        guard !matchingPIDs.isEmpty else {
            // We didn't find the file open in Ghostty's process tree.
            return HeuristicRegistry.HeuristicResult(
                displaysFile: false,
                visibleFile: false,
                hasTabs: hasTabs,
                debug: ["descendants=\(descendantPIDs.count)", "match=0"]
            )
        }

        var visible = false
        if tabModels.isEmpty {
            // No tab bar exposed. If the file is open under the app, treat it as visible.
            visible = true
        } else if tabModels.count == 1 {
            visible = true
        } else {
            // Map file-holding process to tab via cwd -> tab title matching.
            var best: (score: Int, selected: Bool)?
            for pid in matchingPIDs {
                guard let cwd = ProcessInspector.processCWD(pid: pid) else { continue }
                let matcher = TitleMatcher(cwd: cwd)
                for tab in tabModels {
                    let score = matcher.score(against: tab.title)
                    guard score > 0 else { continue }
                    if best == nil || score > best!.score {
                        best = (score: score, selected: tab.selected)
                    }
                }
            }
            if let best {
                visible = best.selected
            }
        }

        return HeuristicRegistry.HeuristicResult(
            displaysFile: true,
            visibleFile: visible,
            hasTabs: hasTabs,
            debug: ["descendants=\(descendantPIDs.count)", "match=\(matchingPIDs.count)"]
        )
    }

    private struct TabModel: Sendable {
        let title: String
        let selected: Bool
    }

    private static func extractTabs(from window: AXUIElement) -> [TabModel] {
        guard let tabGroup = Accessibility.findFirstDescendant(of: window, where: { el in
            Accessibility.role(of: el) == kAXTabGroupRole
        }) else { return [] }

        let radios = Accessibility.children(of: tabGroup).filter { child in
            Accessibility.role(of: child) == kAXRadioButtonRole
        }

        return radios.compactMap { (r) -> TabModel? in
            guard let title = Accessibility.title(of: r) else { return nil }
            let selected = Accessibility.boolValue(r, kAXValueAttribute) ?? false
            return TabModel(title: title, selected: selected)
        }
    }

    private struct TitleMatcher {
        let cwd: String
        let home: String
        let lastComponent: String
        let homeRelativeFull: String?
        let homeRelativeAbbrev: String?

        init(cwd: String) {
            self.cwd = (cwd as NSString).standardizingPath
            self.home = NSHomeDirectory()
            self.lastComponent = URL(fileURLWithPath: self.cwd).lastPathComponent
            self.homeRelativeFull = TitleMatcher.makeHomeRelativeFull(cwd: self.cwd, home: self.home)
            self.homeRelativeAbbrev = TitleMatcher.makeHomeRelativeAbbrev(cwd: self.cwd, home: self.home)
        }

        func score(against title: String) -> Int {
            var score = 0
            if let abbr = homeRelativeAbbrev, title.contains(abbr) { score += 10 }
            if let full = homeRelativeFull, title.contains(full) { score += 5 }
            if !lastComponent.isEmpty, title.contains(lastComponent) { score += 1 }
            return score
        }

        private static func makeHomeRelativeFull(cwd: String, home: String) -> String? {
            guard cwd.hasPrefix(home + "/") else { return nil }
            let rel = String(cwd.dropFirst(home.count + 1))
            guard !rel.isEmpty else { return "~" }
            return "~/" + rel
        }

        private static func makeHomeRelativeAbbrev(cwd: String, home: String) -> String? {
            guard cwd.hasPrefix(home + "/") else { return nil }
            let rel = String(cwd.dropFirst(home.count + 1))
            let comps = rel.split(separator: "/")
            guard !comps.isEmpty else { return nil }
            if comps.count == 1 { return "~/" + String(comps[0]) }

            var out: [String] = []
            out.reserveCapacity(comps.count)
            for (i, c) in comps.enumerated() {
                if i == comps.count - 1 {
                    out.append(String(c))
                } else {
                    out.append(String(c.prefix(1)))
                }
            }
            return "~/" + out.joined(separator: "/")
        }
    }
}

#endif

