import Foundation

import AppKit
import ApplicationServices

enum Revealer {
    private static let ghosttyBundleID = "com.mitchellh.ghostty"
    private static let vscodeOSSBundleID = "com.visualstudio.code.oss"
    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    @discardableResult
    static func reveal(target: URL, in usage: AppUsage) -> Bool {
        guard Accessibility.isTrusted() else { return false }
        guard let running = NSRunningApplication(processIdentifier: usage.pid) else { return false }
        if usage.isFrontmost && usage.isTabDisplayingFileVisible { return true }

        let targetPath = PathNormalizer.normalizeFileURL(target).path
        let targetName = (targetPath as NSString).lastPathComponent

        guard let match = bestMatch(
            bundleID: usage.bundleID,
            pid: usage.pid,
            targetPath: targetPath,
            targetName: targetName
        ) else { return false }

        return reveal(match: match, app: running)
    }

    private struct WindowMatch {
        let window: AXUIElement
        let tab: AXUIElement?
        let score: Int
    }

    private static func bestMatch(
        bundleID: String,
        pid: pid_t,
        targetPath: String,
        targetName: String
    ) -> WindowMatch? {
        if bundleID == ghosttyBundleID {
            return bestGhosttyMatch(pid: pid, targetPath: targetPath)
        }

        if isVSCodeFamily(bundleID) {
            return bestVSCodeLikeMatch(pid: pid, targetPath: targetPath, targetName: targetName)
        }

        return bestStandardMatch(pid: pid, targetPath: targetPath, targetName: targetName)
    }

    private static func isVSCodeFamily(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.microsoft.VSCode")
            || bundleID == vscodeOSSBundleID
            || bundleID == cursorBundleID
    }

    private static func bestStandardMatch(pid: pid_t, targetPath: String, targetName: String) -> WindowMatch? {
        var best: WindowMatch?

        for window in windows(pid: pid) {
            var score = 0
            var tab: AXUIElement?

            if visibleDocumentPath(window: window) == targetPath {
                score += 120
            }

            if let tabMatch = findTabByTitle(in: window, targetName: targetName) {
                tab = tabMatch
                score += 100
                if Accessibility.boolValue(tabMatch, kAXValueAttribute) == true {
                    score += 20
                }
            }

            if windowContainsPath(window, targetPath: targetPath, targetBasename: targetName) {
                score += 80
            }

            guard score > 0 else { continue }
            let candidate = WindowMatch(window: window, tab: tab, score: score)
            if best == nil || candidate.score > best!.score { best = candidate }
        }

        return best
    }

    private struct GhosttyTab {
        let window: AXUIElement
        let element: AXUIElement
        let title: String
        let selected: Bool
    }

    private static func bestGhosttyMatch(pid: pid_t, targetPath: String) -> WindowMatch? {
        let appWindows = windows(pid: pid)
        guard !appWindows.isEmpty else { return nil }

        var tabs: [GhosttyTab] = []
        tabs.reserveCapacity(8)

        for window in appWindows {
            tabs.append(contentsOf: extractGhosttyTabs(window: window))
        }

        let descendantPIDs = ProcessInspector.descendantPIDs(of: pid)
        var matchingPIDs: [pid_t] = []
        matchingPIDs.reserveCapacity(4)
        for childPID in descendantPIDs {
            if ProcessInspector.processHasOpenFile(pid: childPID, path: targetPath) {
                matchingPIDs.append(childPID)
            }
        }
        let matchingTTYs = Set(matchingPIDs.compactMap { ProcessInspector.processTTY(pid: $0) })

        guard !matchingPIDs.isEmpty else { return nil }

        if tabs.isEmpty {
            // No exposed tabs; just raise a window for the matching app.
            return WindowMatch(window: appWindows[0], tab: nil, score: 10)
        }

        var best: (score: Int, tab: GhosttyTab)?
        for matchingPID in matchingPIDs {
            guard let cwd = ProcessInspector.processCWD(pid: matchingPID) else { continue }
            let matcher = GhosttyTitleMatcher(cwd: cwd)
            for tab in tabs {
                let score = matcher.score(against: tab.title)
                guard score > 0 else { continue }
                if best == nil || score > best!.score {
                    best = (score: score, tab: tab)
                }
            }
        }

        if let best {
            return WindowMatch(window: best.tab.window, tab: best.tab.element, score: 200 + best.score)
        }

        if let tab = bestGhosttyTTYFallbackTab(tabs: tabs, matchingTTYs: matchingTTYs) {
            return WindowMatch(window: tab.window, tab: tab.element, score: 150)
        }

        return nil
    }

    private static func bestGhosttyTTYFallbackTab(tabs: [GhosttyTab], matchingTTYs: Set<String>) -> GhosttyTab? {
        guard !tabs.isEmpty else { return nil }
        guard !matchingTTYs.isEmpty else { return nil }
        guard let currentTTY = ProcessInspector.processTTY(pid: getpid()) else { return nil }

        if matchingTTYs.contains(currentTTY) {
            return tabs.first(where: { $0.selected })
        }

        return tabs.first(where: { !$0.selected })
    }

    private static func extractGhosttyTabs(window: AXUIElement) -> [GhosttyTab] {
        guard let tabGroup = Accessibility.findFirstDescendant(of: window, where: { el in
            Accessibility.role(of: el) == kAXTabGroupRole
        }) else { return [] }

        let radios = Accessibility.children(of: tabGroup).filter { child in
            Accessibility.role(of: child) == kAXRadioButtonRole
        }

        return radios.compactMap { radio in
            guard let title = Accessibility.title(of: radio) else { return nil }
            let selected = Accessibility.boolValue(radio, kAXValueAttribute) ?? false
            return GhosttyTab(window: window, element: radio, title: title, selected: selected)
        }
    }

    private static func bestVSCodeLikeMatch(pid: pid_t, targetPath: String, targetName: String) -> WindowMatch? {
        var best: WindowMatch?

        for window in windows(pid: pid) {
            var score = 0
            var tab: AXUIElement?

            if visibleDocumentPath(window: window) == targetPath {
                score += 130
            }

            if let tabMatch = findVSCodeTab(in: window, targetName: targetName) {
                tab = tabMatch.element
                score += tabMatch.score
                if Accessibility.boolValue(tabMatch.element, kAXValueAttribute) == true {
                    score += 10
                }
            }

            if windowContainsPath(window, targetPath: targetPath, targetBasename: targetName) {
                score += 90
            }

            guard score > 0 else { continue }
            let candidate = WindowMatch(window: window, tab: tab, score: score)
            if best == nil || candidate.score > best!.score { best = candidate }
        }

        return best
    }

    private struct TabScore {
        let element: AXUIElement
        let score: Int
    }

    private static func findVSCodeTab(in window: AXUIElement, targetName: String) -> TabScore? {
        var best: TabScore?

        forEachDescendantUntil(of: window, maxNodes: 180_000) { el in
            guard Accessibility.role(of: el) == kAXRadioButtonRole else { return true }
            guard Accessibility.stringValue(el, kAXSubroleAttribute) == "AXTabButton" else { return true }

            let label = firstNonEmpty([
                Accessibility.stringValue(el, kAXDescriptionAttribute),
                Accessibility.stringValue(el, kAXTitleAttribute),
                Accessibility.stringValue(el, kAXHelpAttribute),
            ]) ?? ""

            let normalized = normalizeVSCodeTabTitle(label)
            let score = scoreForTabLabel(normalized, targetName: targetName)
            guard score > 0 else { return true }

            let candidate = TabScore(element: el, score: score)
            if best == nil || candidate.score > best!.score { best = candidate }
            return true
        }

        return best
    }

    private static func normalizeVSCodeTabTitle(_ label: String) -> String {
        var s = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("Preview ") {
            s = String(s.dropFirst("Preview ".count))
        }
        if let bullet = s.firstIndex(of: "•") {
            s = String(s[..<bullet])
        }
        if let comma = s.firstIndex(of: ",") {
            s = String(s[..<comma])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scoreForTabLabel(_ label: String, targetName: String) -> Int {
        if label == targetName { return 120 }
        if label.hasSuffix("/" + targetName) { return 100 }
        if label.contains(targetName) { return 80 }
        return 0
    }

    private static func reveal(match: WindowMatch, app: NSRunningApplication) -> Bool {
        _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        _ = Accessibility.performAction(match.window, kAXRaiseAction)
        _ = Accessibility.setBoolValue(match.window, kAXMainAttribute, true)

        if let tab = match.tab {
            _ = Accessibility.performAction(tab, kAXPressAction)
        }

        usleep(120_000)
        return true
    }

    private static func windows(pid: pid_t) -> [AXUIElement] {
        let axApp = Accessibility.appElement(pid: pid)
        let raw = Accessibility.attributeValue(axApp, kAXWindowsAttribute)
        return (raw as? [AXUIElement])
            ?? (raw as? [AnyObject])?.map { $0 as! AXUIElement }
            ?? []
    }

    private static func visibleDocumentPath(window: AXUIElement) -> String? {
        guard let doc = Accessibility.stringValue(window, kAXDocumentAttribute), !doc.isEmpty else { return nil }
        if let url = URL(string: doc), url.isFileURL {
            return PathNormalizer.normalizeFileURL(url).path
        }
        return nil
    }

    private static func findTabByTitle(in window: AXUIElement, targetName: String) -> AXUIElement? {
        guard let tabGroup = Accessibility.findFirstDescendant(of: window, where: { el in
            Accessibility.role(of: el) == kAXTabGroupRole
        }) else { return nil }

        let radios = Accessibility.children(of: tabGroup).filter { child in
            Accessibility.role(of: child) == kAXRadioButtonRole
        }

        for tab in radios {
            guard let title = Accessibility.title(of: tab)?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            if title == targetName || title.hasSuffix("/" + targetName) || title.contains(targetName) {
                return tab
            }
        }
        return nil
    }

    private static func windowContainsPath(_ window: AXUIElement, targetPath: String, targetBasename: String) -> Bool {
        var found = false
        forEachDescendantUntil(of: window, maxNodes: 300_000) { el in
            for s in stringsForSearch(element: el) {
                if !s.contains(targetBasename) { continue }
                if extractPaths(from: s).contains(targetPath) {
                    found = true
                    return false
                }
            }
            return true
        }
        return found
    }

    private static func stringsForSearch(element: AXUIElement) -> [String] {
        var out: [String] = []
        out.reserveCapacity(4)

        if let s = Accessibility.stringValue(element, kAXTitleAttribute), !s.isEmpty { out.append(s) }
        if let s = Accessibility.stringValue(element, kAXDescriptionAttribute), !s.isEmpty { out.append(s) }
        if let s = Accessibility.stringValue(element, kAXHelpAttribute), !s.isEmpty { out.append(s) }

        if let raw = Accessibility.attributeValue(element, kAXValueAttribute) {
            if let s = raw as? String, !s.isEmpty {
                out.append(s)
            } else if let s = (raw as? NSAttributedString)?.string, !s.isEmpty {
                out.append(s)
            }
        }

        return out
    }

    private static func extractPaths(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1024 else { return [] }

        let head = trimmed.split(separator: "•", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
        let candidate = head.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.hasPrefix("file://"), let url = URL(string: candidate), url.isFileURL {
            return [PathNormalizer.normalizeFileURL(url).path]
        }

        if candidate.hasPrefix("~/") || candidate.hasPrefix("/") {
            if let url = PathNormalizer.fileURL(from: candidate) { return [url.path] }
            return []
        }

        if let range = candidate.range(of: "/Users/") {
            let suffix = String(candidate[range.lowerBound...])
            let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? suffix
            let cleaned = stripTrailingPathPunctuation(token)
            if let url = PathNormalizer.fileURL(from: cleaned) { return [url.path] }
        } else if let range = candidate.range(of: "~/") {
            let suffix = String(candidate[range.lowerBound...])
            let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? suffix
            let cleaned = stripTrailingPathPunctuation(token)
            if let url = PathNormalizer.fileURL(from: cleaned) { return [url.path] }
        }

        return []
    }

    private static func stripTrailingPathPunctuation(_ s: String) -> String {
        var out = s
        while let last = out.last, ")]},.;'\"".contains(last) {
            out.removeLast()
        }
        return out
    }

    private static func firstNonEmpty(_ items: [String?]) -> String? {
        for s in items {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
        }
        return nil
    }

    private static func forEachDescendantUntil(
        of root: AXUIElement,
        maxNodes: Int,
        _ shouldContinue: (AXUIElement) -> Bool
    ) {
        var queue: [AXUIElement] = [root]
        queue.reserveCapacity(512)
        var idx = 0
        var seen = 0

        while idx < queue.count, seen < maxNodes {
            let current = queue[idx]
            idx += 1
            seen += 1

            if !shouldContinue(current) { return }

            let kids = Accessibility.children(of: current)
            if !kids.isEmpty { queue.append(contentsOf: kids) }
        }
    }

    private struct GhosttyTitleMatcher {
        let cwd: String
        let home: String
        let lastComponent: String
        let homeRelativeFull: String?
        let homeRelativeAbbrev: String?

        init(cwd: String) {
            self.cwd = (cwd as NSString).standardizingPath
            self.home = NSHomeDirectory()
            self.lastComponent = URL(fileURLWithPath: self.cwd).lastPathComponent
            self.homeRelativeFull = GhosttyTitleMatcher.makeHomeRelativeFull(cwd: self.cwd, home: self.home)
            self.homeRelativeAbbrev = GhosttyTitleMatcher.makeHomeRelativeAbbrev(cwd: self.cwd, home: self.home)
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
