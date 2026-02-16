import Foundation

import AppKit
import ApplicationServices

enum Revealer {
    struct WindowMatch {
        let window: AXUIElement
        let tab: AXUIElement?
        let score: Int
    }

    @discardableResult
    static func reveal(target: URL, in usage: AppUsage, registry: HeuristicRegistry = .default) -> Bool {
        guard Accessibility.isTrusted() else { return false }
        if usage.isFrontmost && usage.isTabDisplayingFileVisible { return true }

        let normalizedTarget = PathNormalizer.normalizeFileURL(target)
        let entries = registry.applicable(bundleID: usage.bundleID)
        for entry in entries {
            guard let reveal = entry.reveal else { continue }
            if reveal(usage, normalizedTarget) {
                return true
            }
        }
        return false
    }

    @discardableResult
    static func reveal(match: WindowMatch, pid: pid_t) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return false }

        _ = running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        _ = Accessibility.performAction(match.window, kAXRaiseAction)
        _ = Accessibility.setBoolValue(match.window, kAXMainAttribute, true)

        if let tab = match.tab {
            _ = Accessibility.performAction(tab, kAXPressAction)
        }

        usleep(120_000)
        return true
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        let axApp = Accessibility.appElement(pid: pid)
        let raw = Accessibility.attributeValue(axApp, kAXWindowsAttribute)
        return (raw as? [AXUIElement])
            ?? (raw as? [AnyObject])?.map { $0 as! AXUIElement }
            ?? []
    }

    static func visibleDocumentPath(window: AXUIElement) -> String? {
        guard let doc = Accessibility.stringValue(window, kAXDocumentAttribute), !doc.isEmpty else { return nil }
        if let url = URL(string: doc), url.isFileURL {
            return PathNormalizer.normalizeFileURL(url).path
        }
        return nil
    }

    static func windowContainsPath(_ window: AXUIElement, targetPath: String, targetBasename: String) -> Bool {
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

    static func stringsForSearch(element: AXUIElement) -> [String] {
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

    static func extractPaths(from raw: String) -> [String] {
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

    static func stripTrailingPathPunctuation(_ s: String) -> String {
        var out = s
        while let last = out.last, ")]},.;'\"".contains(last) {
            out.removeLast()
        }
        return out
    }

    static func firstNonEmpty(_ items: [String?]) -> String? {
        for s in items {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
        }
        return nil
    }

    static func forEachDescendantUntil(
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
