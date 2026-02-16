import Foundation

import ApplicationServices

enum StandardMacOSTabHeuristic {
    static func entry() -> HeuristicRegistry.Entry {
        HeuristicRegistry.Entry(
            name: "StandardMacOSTabHeuristic",
            match: .any,
            priority: -100, // ultimate fallback
            run: { app, target in
                evaluate(app: app, target: target)
            },
            reveal: { usage, target in
                reveal(target: target, in: usage)
            }
        )
    }

    @discardableResult
    static func reveal(target: URL, in usage: AppUsage) -> Bool {
        let targetPath = PathNormalizer.normalizeFileURL(target).path
        let targetName = (targetPath as NSString).lastPathComponent
        guard let match = bestRevealMatch(pid: usage.pid, targetPath: targetPath, targetName: targetName) else { return false }
        return Revealer.reveal(match: match, pid: usage.pid)
    }

    private struct WindowScan {
        var displaysFile: Bool = false
        var visibleFile: Bool = false
        var hasTabs: Bool = false
        var debug: [String] = []
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

        let targetURL = PathNormalizer.normalizeFileURL(target)
        let targetName = targetURL.lastPathComponent

        let axApp = Accessibility.appElement(pid: app.pid)
        let rawWindows = Accessibility.attributeValue(axApp, kAXWindowsAttribute)
        let windows =
            (rawWindows as? [AXUIElement])
            ?? (rawWindows as? [AnyObject])?.map { $0 as! AXUIElement }
            ?? []

        var scan = WindowScan()
        scan.debug.append("windows=\(windows.count)")

        for window in windows {
            let tabs = extractTabs(from: window)
            if !tabs.isEmpty {
                scan.debug.append("tabs=\(tabs.count)")
            }

            let containsTargetByTitle = tabs.contains(where: { $0.title == targetName })

            if let docStr = Accessibility.stringValue(window, kAXDocumentAttribute),
               let docURL = URL(string: docStr),
               docURL.isFileURL {
                let normalizedDoc = PathNormalizer.normalizeFileURL(docURL)
                if normalizedDoc == targetURL {
                    scan.visibleFile = true
                    scan.displaysFile = true
                    scan.debug.append("AXDocument match")
                    if tabs.count > 1 {
                        scan.hasTabs = true
                    }
                }
            }

            if containsTargetByTitle {
                scan.displaysFile = true
                if tabs.count > 1 {
                    scan.hasTabs = true
                }
            }
        }

        if scan.visibleFile { scan.displaysFile = true }

        return HeuristicRegistry.HeuristicResult(
            displaysFile: scan.displaysFile,
            visibleFile: scan.visibleFile,
            hasTabs: scan.hasTabs,
            debug: scan.debug
        )
    }

    private struct TabInfo {
        let title: String
    }

    private static func bestRevealMatch(pid: pid_t, targetPath: String, targetName: String) -> Revealer.WindowMatch? {
        var best: Revealer.WindowMatch?

        for window in Revealer.windows(pid: pid) {
            var score = 0
            var tab: AXUIElement?

            if Revealer.visibleDocumentPath(window: window) == targetPath {
                score += 120
            }

            if let tabMatch = findRevealTabByTitle(in: window, targetName: targetName) {
                tab = tabMatch
                score += 100
                if Accessibility.boolValue(tabMatch, kAXValueAttribute) == true {
                    score += 20
                }
            }

            if Revealer.windowContainsPath(window, targetPath: targetPath, targetBasename: targetName) {
                score += 80
            }

            guard score > 0 else { continue }
            let candidate = Revealer.WindowMatch(window: window, tab: tab, score: score)
            if best == nil || candidate.score > best!.score { best = candidate }
        }

        return best
    }

    private static func findRevealTabByTitle(in window: AXUIElement, targetName: String) -> AXUIElement? {
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

    private static func extractTabs(from window: AXUIElement) -> [TabInfo] {
        guard let tabGroup = Accessibility.findFirstDescendant(of: window, where: { el in
            Accessibility.role(of: el) == kAXTabGroupRole
        }) else {
            return []
        }

        let radios = Accessibility.children(of: tabGroup).filter { child in
            Accessibility.role(of: child) == kAXRadioButtonRole
        }

        return radios.compactMap { (r) -> TabInfo? in
            guard let title = Accessibility.title(of: r) else { return nil }
            return TabInfo(title: title)
        }
    }
}
