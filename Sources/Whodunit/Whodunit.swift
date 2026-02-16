import Foundation


/// Namespace entrypoint for common operations.
public enum Whodunit {
    public static func appsUsing(_ path: String, options: DetectionOptions = .default) -> [AppUsage] {
        guard let resolver = FileEditingResolver(path, options: options) else { return [] }
        return resolver.apps
    }

    @discardableResult
    public static func reveal(_ path: String, options: DetectionOptions = .default) -> Bool {
        guard let resolver = FileEditingResolver(path, options: options) else { return false }
        guard resolver.apps.count == 1, let app = resolver.apps.first else { return false }
        return reveal(path: resolver.target, in: app)
    }

    @discardableResult
    public static func reveal(path: URL, in app: AppUsage) -> Bool {
        Revealer.reveal(target: path, in: app)
    }
}

