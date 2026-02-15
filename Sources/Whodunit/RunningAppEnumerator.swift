import Foundation

#if os(macOS)
import AppKit

public struct AppDescriptor: Sendable, Hashable {
    public let bundleID: String
    public let pid: pid_t
    public let name: String

    public init(bundleID: String, pid: pid_t, name: String) {
        self.bundleID = bundleID
        self.pid = pid
        self.name = name
    }
}

enum RunningAppEnumerator {
    static func enumerate() -> [AppDescriptor] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                let pid = app.processIdentifier
                let name = app.localizedName ?? bundleID
                return AppDescriptor(bundleID: bundleID, pid: pid, name: name)
            }
    }
}

enum FrontmostAppResolver {
    static func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

#endif
