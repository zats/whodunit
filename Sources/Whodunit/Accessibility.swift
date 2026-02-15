import Foundation

#if os(macOS)
import ApplicationServices

enum Accessibility {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func appElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func attributeValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let value else { return nil }
        return value as AnyObject
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let raw = attributeValue(element, kAXChildrenAttribute) else { return [] }
        if let array = raw as? [AXUIElement] { return array }
        if let array = raw as? [AnyObject] { return array.map { $0 as! AXUIElement } }
        return []
    }

    static func role(of element: AXUIElement) -> String? {
        attributeValue(element, kAXRoleAttribute) as? String
    }

    static func title(of element: AXUIElement) -> String? {
        if let title = attributeValue(element, kAXTitleAttribute) as? String, !title.isEmpty {
            return title
        }
        if let desc = attributeValue(element, kAXDescriptionAttribute) as? String, !desc.isEmpty {
            return desc
        }
        return nil
    }

    static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = attributeValue(element, attribute) else { return nil }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }

    static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        attributeValue(element, attribute) as? String
    }

    static func findFirstDescendant(
        of root: AXUIElement,
        maxNodes: Int = 5_000,
        where predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        queue.reserveCapacity(256)
        var seen = 0

        while !queue.isEmpty, seen < maxNodes {
            let current = queue.removeFirst()
            seen += 1

            if predicate(current) { return current }

            let kids = children(of: current)
            if !kids.isEmpty { queue.append(contentsOf: kids) }
        }

        return nil
    }
}

#endif
