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
            }
        )
    }

    private struct WindowScan {
        var anyAX: Bool = false
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
        scan.anyAX = true
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

        guard scan.anyAX else { return nil }
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
        let selected: Bool
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
            let selected = Accessibility.boolValue(r, kAXValueAttribute) ?? false
            return TabInfo(title: title, selected: selected)
        }
    }
}

