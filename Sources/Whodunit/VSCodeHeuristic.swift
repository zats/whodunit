import Foundation

#if os(macOS)
import ApplicationServices

enum VSCodeHeuristic {
    private static let textFileEditorMementoKey = "memento/workbench.editors.files.textFileEditor"

    static func entries() -> [HeuristicRegistry.Entry] {
        [
            .init(
                name: "VSCodeHeuristic",
                match: .bundleIDPrefix("com.microsoft.VSCode"),
                priority: 40,
                run: { app, target in
                    evaluate(app: app, target: target)
                }
            ),
            .init(
                name: "VSCodeHeuristic",
                match: .bundleID("com.visualstudio.code.oss"),
                priority: 40,
                run: { app, target in
                    evaluate(app: app, target: target)
                }
            ),
            .init(
                name: "VSCodeHeuristic",
                match: .bundleID("com.todesktop.230313mzl4w4u92"), // Cursor
                priority: 40,
                run: { app, target in
                    evaluate(app: app, target: target)
                }
            ),
        ]
    }

    static func evaluate(app: AppDescriptor, target: URL) -> HeuristicRegistry.HeuristicResult? {
        guard Accessibility.isTrusted() else {
            return .init(displaysFile: nil, visibleFile: nil, hasTabs: nil, debug: ["AX not trusted"])
        }

        let targetURL = PathNormalizer.normalizeFileURL(target)
        let targetPath = targetURL.path
        let targetBasename = targetURL.lastPathComponent

        let axApp = Accessibility.appElement(pid: app.pid)
        let rawWindows = Accessibility.attributeValue(axApp, kAXWindowsAttribute)
        let windows =
            (rawWindows as? [AXUIElement])
            ?? (rawWindows as? [AnyObject])?.map { $0 as! AXUIElement }
            ?? []

        var displaysFile = false
        var visibleFile = false
        var hasTabs = false

        var debug: [String] = []
        debug.append("windows=\(windows.count)")

        for window in windows {
            let windowDocPath = visibleDocumentPath(window: window)
            let visibleInThisWindow = (windowDocPath == targetPath)
            var containsTarget = visibleInThisWindow

            if !containsTarget {
                containsTarget = searchForTargetPath(
                    in: window,
                    targetPath: targetPath,
                    targetBasename: targetBasename,
                    maxNodes: 800_000
                )
            }

            guard containsTarget else { continue }

            displaysFile = true
            if visibleInThisWindow { visibleFile = true }
            if hasAtLeastTwoFileishTabs(window: window, maxNodes: 120_000) { hasTabs = true }
        }

        // VS Code does not reliably expose full paths for background tabs via Accessibility.
        // Use its workspaceStorage state DB as a fallback for "open somewhere" detection.
        if !displaysFile {
            let state = stateFromWorkspaceStorage(bundleID: app.bundleID, targetPath: targetPath)
            if state.open {
                displaysFile = true
                if state.openEditorsCount >= 2 { hasTabs = true }
            }
        }

        if visibleFile { displaysFile = true }

        debug.append("displays=\(displaysFile)")
        debug.append("visible=\(visibleFile)")
        debug.append("hasTabs=\(hasTabs)")

        return .init(displaysFile: displaysFile, visibleFile: visibleFile, hasTabs: hasTabs, debug: debug)
    }

    private static func visibleDocumentPath(window: AXUIElement) -> String? {
        guard let doc = Accessibility.stringValue(window, kAXDocumentAttribute), !doc.isEmpty else { return nil }
        if let url = URL(string: doc), url.isFileURL {
            return PathNormalizer.normalizeFileURL(url).path
        }
        return nil
    }

    private static func hasAtLeastTwoFileishTabs(window: AXUIElement, maxNodes: Int) -> Bool {
        var count = 0

        forEachDescendantUntil(of: window, maxNodes: maxNodes) { el in
            guard Accessibility.role(of: el) == kAXRadioButtonRole else { return true }
            guard Accessibility.stringValue(el, kAXSubroleAttribute) == "AXTabButton" else { return true }

            let label =
                firstNonEmpty([
                    Accessibility.stringValue(el, kAXDescriptionAttribute),
                    Accessibility.stringValue(el, kAXTitleAttribute),
                    Accessibility.stringValue(el, kAXHelpAttribute),
                ])

            guard let label, isFileishTabLabel(label) else { return true }

            count += 1
            return count < 2
        }

        return count >= 2
    }

    private static func searchForTargetPath(
        in window: AXUIElement,
        targetPath: String,
        targetBasename: String,
        maxNodes: Int
    ) -> Bool {
        var found = false

        forEachDescendantUntil(of: window, maxNodes: maxNodes) { el in
            for s in stringsForSearch(element: el) {
                if !s.contains(targetBasename) { continue }
                for path in extractPaths(from: s) {
                    if path == targetPath {
                        found = true
                        return false
                    }
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

        // Common VS Code UX: "<path> • Modified" and similar.
        let head = trimmed.split(separator: "•", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
        let candidate = head.trimmingCharacters(in: .whitespacesAndNewlines)

        var paths: [String] = []
        paths.reserveCapacity(2)

        if candidate.hasPrefix("file://"), let url = URL(string: candidate), url.isFileURL {
            paths.append(PathNormalizer.normalizeFileURL(url).path)
            return paths
        }

        if candidate.hasPrefix("~/") || candidate.hasPrefix("/") {
            if let url = PathNormalizer.fileURL(from: candidate) {
                paths.append(url.path)
            }
            return paths
        }

        // Scan for an embedded path-like substring, but keep it cheap.
        if let range = candidate.range(of: "/Users/") {
            let suffix = String(candidate[range.lowerBound...])
            let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? suffix
            let cleaned = stripTrailingPathPunctuation(token)
            if let url = PathNormalizer.fileURL(from: cleaned) {
                paths.append(url.path)
            }
        } else if let range = candidate.range(of: "~/") {
            let suffix = String(candidate[range.lowerBound...])
            let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? suffix
            let cleaned = stripTrailingPathPunctuation(token)
            if let url = PathNormalizer.fileURL(from: cleaned) {
                paths.append(url.path)
            }
        }

        return paths
    }

    private static func stripTrailingPathPunctuation(_ s: String) -> String {
        var out = s
        while let last = out.last, ")]},.;'\"".contains(last) {
            out.removeLast()
        }
        return out
    }

    private struct WorkspaceState: Sendable {
        let open: Bool
        let openEditorsCount: Int
    }

    private static func stateFromWorkspaceStorage(bundleID: String, targetPath: String) -> WorkspaceState {
        guard let workspaceStorage = workspaceStorageDirectory(bundleID: bundleID) else {
            return .init(open: false, openEditorsCount: 0)
        }

        let dbs = mostRecentlyModifiedStateDBs(in: workspaceStorage, maxCount: 80)
        guard !dbs.isEmpty else { return .init(open: false, openEditorsCount: 0) }

        for dbURL in dbs {
            guard let urls = openTextEditorFileURLs(fromStateDB: dbURL) else { continue }
            if urls.contains(where: { $0.path == targetPath }) {
                return .init(open: true, openEditorsCount: urls.count)
            }
        }

        return .init(open: false, openEditorsCount: 0)
    }

    private static func workspaceStorageDirectory(bundleID: String) -> URL? {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")

        let roots: [String]
        if bundleID.hasPrefix("com.microsoft.VSCode") {
            roots = ["Code", "Code - Insiders", "Code - Exploration"]
        } else if bundleID == "com.visualstudio.code.oss" {
            roots = ["Code - OSS"]
        } else if bundleID == "com.todesktop.230313mzl4w4u92" {
            roots = ["Cursor"]
        } else {
            roots = ["Code"]
        }

        for r in roots {
            let dir = support
                .appendingPathComponent(r)
                .appendingPathComponent("User")
                .appendingPathComponent("workspaceStorage")
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }

        return nil
    }

    private static func mostRecentlyModifiedStateDBs(in dir: URL, maxCount: Int) -> [URL] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]

        var out: [(URL, Date)] = []
        out.reserveCapacity(32)

        let e = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        while let item = e?.nextObject() as? URL {
            guard item.lastPathComponent == "state.vscdb" else { continue }
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let m = values.contentModificationDate else { continue }
            out.append((item, m))
        }

        out.sort(by: { $0.1 > $1.1 })
        return out.prefix(maxCount).map(\.0)
    }

    private static func openTextEditorFileURLs(fromStateDB dbURL: URL) -> [URL]? {
        guard let db = SQLiteKVStore.DB(url: dbURL) else { return nil }
        guard let raw = db.valueData(forKey: textFileEditorMementoKey), !raw.isEmpty else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
        guard let entries = json["textEditorViewState"] as? [Any] else { return nil }

        var urls: [URL] = []
        urls.reserveCapacity(min(entries.count, 32))

        for entry in entries {
            guard let pair = entry as? [Any], let first = pair.first as? String else { continue }
            guard let u = URL(string: first), u.isFileURL else { continue }
            urls.append(PathNormalizer.normalizeFileURL(u))
        }

        return urls.isEmpty ? nil : urls
    }

    private static func isFileishTabLabel(_ label: String) -> Bool {
        let s = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 3, s.count <= 220 else { return false }
        guard s.contains(".") else { return false }

        // Exclude view tabs with keyboard shortcuts.
        if s.contains("⇧") || s.contains("⌘") || s.contains("⌃") { return false }
        if s.contains("(Ctrl") { return false }
        return true
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
}

#endif
